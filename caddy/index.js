const logger = require('../logging/log');
const { rateLimitIncr, checkCache, updateCache } = require("../cache/redis");
const { getDomainOfRequestFromGet, stripSubdomainsFromHost } = require('../utils')
const { resolveEns } = require("../ens/ens");
const configuration = require('../configuration/config');
const {checkIfDomainIsBlacklisted} = require('../blacklist')
const {blockedForLegalReasons} = require('../expressErrors')
const caddy = async (req, res) => {
    let ensDomain = getDomainOfRequestFromGet(req);
    if (!ensDomain) {
        res.status(422);
        res.end();
        return
    }
    if(checkIfDomainIsBlacklisted(ensDomain)) {
        blockedForLegalReasons(res)
        return
    }
    const parentDomain = stripSubdomainsFromHost(ensDomain)
    let isCached = await checkCache(ensDomain);
    if (isCached === false) {
        if (parentDomain && configuration.ask.rate.enabled) {
            logger.info(`caddy: checking for ${parentDomain} rate limit`)
            const rateLimit = await rateLimitIncr(`rateLimit/caddy/${parentDomain}`, configuration.ask.rate.limit, configuration.ask.rate.period)
            if(rateLimit.surpassed) {
                logger.info(`caddy: rate limit exceeded for ${parentDomain} in query for ${ensDomain}, rate limit expires in ${rateLimit.keyTtl} seconds`)
                res.status(422)
                res.end()
                return;
            }
        } else if (configuration.ask.rate.enabled) {
            logger.error(`caddy: ignoring rate limit check, ${ensDomain} does not have a valid parent domain`)
        }
        let location = await resolveEns(ensDomain);
        await updateCache(ensDomain, location);
        switch (location.codec) {
            case 422:
                res.status(422);
                res.end();
                break;
            default:
                res.send(location);
                res.status(200);
                res.end();
                break;
        }
    } else {
        switch (isCached.codec) {
            case "url":
                res.status(422);
                res.end();
                break;
            case 422:
                res.status(422);
                res.end();
                break;
            default:
                res.send(isCached);
                res.status(200);
                res.end();
                break;
        }
    }
}

module.exports = caddy