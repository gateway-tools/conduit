const http = require('http');
const https = require('https');
const httpProxy = require('http-proxy');
const configuration = require("../configuration/config");
const express = require('express');
const logger = require("../logging/log");
const cluster = require('cluster');
const totalCPUs = require('os').cpus().length;
const { updateCache, checkCache } = require("../cache/redis");
const { resolveEns } = require("../ens/ens");
const bodyParser = require('body-parser')
const { dnsqueryPost, dnsqueryGet } = require("../dnsquery")
const caddy = require('../caddy')
const { isError, notSupported, blockedForLegalReasons } = require("../expressErrors")
const cors = require('cors')
const { checkIfDomainIsBlacklisted } = require('../blacklist')

const keepAliveAgent = new http.Agent({
  keepAlive: true,
  maxSockets: 1000
});

const keepAliveAgentTls = new https.Agent({
  keepAlive: true,
  maxSockets: 1000
});

const proxy = httpProxy.createProxyServer({
  agent: keepAliveAgent,
  proxyTimeout: 120000,
  timeout: 120000,
});

const proxyTls = httpProxy.createProxyServer({
  agent: keepAliveAgentTls,
  secure: true,
  proxyTimeout: 120000,
  timeout: 120000,
});

const askExpress = express()
const dnsqueryExpress = express()

const ipfsTarget = configuration.ipfs.backend;
const arweaveTarget = configuration.arweave.backend;
const swarmTarget = configuration.swarm.backend;
const ingressTld = configuration.global.tld;

proxy.on('error', function (err, req, res) {
  logger.error("Failed to proxy request", err);
})

proxyTls.on('error', function (err, req, res) {
  logger.error("Failed to proxy TLS request", err);
})

function proxyRequest(target, path = "none", req, res) {
  target = (path !== "none") ? target + path : target

  if (target.startsWith("https://")) {
    try {
      proxyTls.web(req, res, {
        target,
        changeOrigin: true,
        secure: true,
        followRedirects: true
      });
    } catch (err) {
      logger.error("Failed to proxy HTTPS request", err);
      isError(res);
    }
  } else {
    try {
      proxy.web(req, res, {
        target,
        changeOrigin: true,
        secure: false,
        followRedirects: true
      });
    } catch (err) {
      logger.error("Failed to proxy dWeb HTTP request", err);
      isError(res);
    }
  }
}

function requestHandler(content, req, res) {
  let cachedLocation = content.path;
  let cachedCodec = content.codec;
  switch (cachedCodec) {
    case "ipns-ns":
    case "ipfs-ns":
      proxyRequest(ipfsTarget, cachedLocation, req, res);
      break;
    case "arweave-ns":
      proxyRequest(arweaveTarget, cachedLocation, req, res);
      break;
    case "swarm":
      proxyRequest(swarmTarget, cachedLocation, req, res);
      break;
    default:
      return notSupported(res);
  }
}


dnsqueryExpress.use(cors())
dnsqueryExpress.post('/dns-query', [bodyParser.raw({ type: 'application/dns-message', limit: '2kb' })], dnsqueryPost)
dnsqueryExpress.get('/dns-query', [bodyParser.json({ limit: '2kb' })], dnsqueryGet)
askExpress.get('/ask', caddy)

function start() {
  if (cluster.isMaster && process.env.NODE_ENV !== "test") {
    for (let i = 0; i < totalCPUs; i++) {
      cluster.fork();
    }
  } else {
    try {
      const server = http.createServer(function (req, res) {
        let hostHeader = req.headers["host"];
        let hostname = hostHeader.split(":")[0]
        if (hostname.endsWith(ingressTld)) {
          hostname = hostname.substring(0, hostname.length - 5);
        }
        if (!hostname.endsWith('.eth')) {
          notSupported(res);
        } else {
          if (checkIfDomainIsBlacklisted(hostname)) {
            blockedForLegalReasons(res)
            return
          }
          (async () => {
            let isCached = await checkCache(hostname);
            if (isCached === false) {
              let location = await resolveEns(hostname);
              if (location.codec === 404) {
                await updateCache(hostname, location);
                notSupported(res);
              } else {
                await updateCache(hostname, location);
                requestHandler(location, req, res);
              }
            } else {
              requestHandler(isCached, req, res);
            }
          })();
        }
      }).listen(configuration.router.listen, function () {
        logger.info(`Server started on PID ${process.pid} listening on ${configuration.router.listen}`)
        switch (configuration.ask.enabled) {
          case "true":
            askExpress.listen(configuration.ask.listen, () => {
              logger.info(`Ask server started, listening on ${configuration.ask.listen}`)
            });
            break;
        }
        if (configuration.dnsquery.enabled) {
          dnsqueryExpress.listen(configuration.dnsquery.listen, () => {
            logger.info(`DOH server started, listening on ${configuration.dnsquery.listen}`)
          })
        }
      })
    } catch (err) {
      logger.error("Error starting server!", err)
    }
  }
}

exports.start = start;
