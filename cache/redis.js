const Redis = require("ioredis");
const logger = require("../logging/log");
const NodeCache = require("node-cache");
const configuration = require("../configuration/config");
const { default: Redlock } = require("redlock");
const { redis } = require("../configuration/config");

const cacheTtl = configuration.cache.ttl;

const localCache = new NodeCache({
  stdTTL: cacheTtl,
  checkperiod: cacheTtl
});

const redisClient = new Redis(configuration.redis.url);
const redlockClient = new Redis(configuration.redis.url);

const redlock = new Redlock(
  [redlockClient],
  {
    driftFactor: 0.01,
    retryCount: 100000,
    retryDelay: 5000,
    retryJitter: 200,
    automaticExtensionThreshold: 500
  }
);

async function checkCache(hostname) {
  let memCached = await localCache.get(hostname);
  if (memCached === undefined) {
    try {
      let redisCached = await redisClient.get(hostname);
      if (redisCached === null) {
        return false
      } else {
        // Populate local in-memory cache from Redis
        localCache.set(hostname, redisCached);
        let cachedResult = JSON.parse(redisCached);
        return cachedResult;
      }
    } catch (err) {
      logger.error("Could not check Redis cache", err)
    }
  } else {
    return JSON.parse(memCached);
  }
}

async function updateCache(hostname, content) {
  let contentObject = JSON.stringify(content);
  localCache.set(hostname, contentObject);
  try {
    await redisClient.set(hostname, contentObject);
    await redisClient.expire(hostname, cacheTtl);
  } catch (err) {
    logger.error("Error adding item to cache", err);
  }
}


async function rateLimitIncr(key, amount, timeForAmount) {
  const keyTtl = await redisClient.ttl(key)
  logger.debug(`rateLimitIncr: ${key} has ttl ${keyTtl}`)
  var times = await redisClient.incr(key)
  if(!keyTtl || keyTtl < 0) {
    logger.info(`rateLimitIncr: setting TTL for ${key} = ${timeForAmount} seconds`)
    await redisClient.expire(key, timeForAmount)
  }

  return {
    times,
    periodInSeconds: timeForAmount,
    keyTtl,
    surpassed: times > amount
  }
}

module.exports = {
  updateCache,
  checkCache,
  redlockClient,
  redlock,
  rateLimitIncr
}