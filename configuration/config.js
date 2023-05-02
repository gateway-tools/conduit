const createHostname = (...args) => {
    var ret = []
    for(const v of args) {
        ret.push(v.replace('.',''))
    }

    return ret
}

const defaultTld = process.env.DOMAIN_TLD || '.link'
const defaultHostname = process.env.DOMAIN_TLD_HOSTNAME || "eth"
const defaultHost = createHostname(defaultHostname, defaultTld)


var configuration = {};

// globals
configuration.global = {};
configuration.global.tld = {};
configuration.global.tld = defaultTld;

// Ethereum JSON RPC endpoint
configuration.ethereum = {};
configuration.ethereum.rpc = {};
configuration.ethereum.rpc = process.env.ETH_RPC_ENDPOINT || "http://127.0.0.1:8545";

// Storage backends
configuration.ipfs = {};
configuration.ipfs.backend = {};
configuration.ipfs.backend = process.env.IPFS_TARGET || "http://127.0.0.1:8080";
configuration.arweave = {};
configuration.arweave.backend = {};
configuration.arweave.backend = process.env.ARWEAVE_TARGET || "https://arweave.net";
configuration.swarm = {};
configuration.swarm.backend = {};
configuration.swarm.backend = process.env.SWARM_TARGET || "https://api.gateway.ethswarm.org";

// Cache
configuration.redis = {};
configuration.cache = {};
configuration.redis.url = {};
configuration.redis.url = process.env.REDIS_URL || "redis://127.0.0.1:6379"
configuration.cache.ttl = {};
configuration.cache.ttl = process.env.CACHE_TTL || 300

// Proxy
configuration.router = {};
configuration.router.listen = {};
configuration.router.listen = process.env.LISTEN_PORT || 8888;
configuration.router.origin = "Conduit"

// Server ask endpoint
configuration.ask = {};
configuration.ask.listen = {};
configuration.ask.listen = process.env.ASK_LISTEN_PORT || 9090
configuration.ask.host = defaultHost
configuration.ask.enabled = process.env.ASK_ENABLED || "false"
configuration.ask.rate = {}
configuration.ask.rate.limit = Number(process.env.ASK_RATE_LIMIT ?? 10)
//configuration.ask.rate.period: input in minutes, actual value in seconds
configuration.ask.rate.period = Number(process.env.ASK_RATE_PERIOD ?? 15) * 60
configuration.ask.rate.enabled = configuration.ask.rate.limit > 0

//dns-query isolated endpoint (DOH)
configuration.dnsquery = {}
configuration.dnsquery.listen = process.env.DNSQUERY_LISTEN_PORT || 11000
//TODO: not used?
configuration.dnsquery.host = defaultHost
configuration.dnsquery.enabled = Boolean(process.env.DNSQUERY_ENABLED ?? true)


// Tests
configuration.tests = {};
configuration.tests.hostname = "vitalik.eth"

configuration.ens = {}

configuration.resolver = {}
configuration.resolver.blacklist = []

module.exports = configuration;
