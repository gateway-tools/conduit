const { ethers } = require("ethers");
const urlRegexSafe = require('url-regex-safe');
const configuration = require("../configuration/config");
const logger = require("../logging/log")
const { checkCache, redlock } = require("../cache/redis");
const CID = require('multiformats/cid').CID
const contentHash = require('@ensdomains/content-hash')
const raw = require('multiformats/codecs/raw')

const provider = new ethers.providers.JsonRpcProvider(configuration.ethereum.rpc);

function parseRecord(content, txt = "none") {
  var path;
  var cleanPath;
  var codec;
  switch (txt) {
    case "contenthash":
      switch (true) {
        case (content.startsWith("ipfs://")):
          cleanPath = content.split("ipfs://")[1];
          path = "/ipfs/" + cleanPath + "/";
          codec = "ipfs-ns";
          break;
        case (content.startsWith("ipns://")):
          cleanPath = content.split("ipns://")[1];
          path = "/ipns/" + cleanPath + "/";
          codec = "ipns-ns";
          break;
        case (content.startsWith("sia://")):
          cleanPath = content.split("sia://")[1];
          path = "/" + cleanPath + "/";
          codec = "skynet-ns";
          break;
        case (content.startsWith("arweave://")):
          cleanPath = content.split("arweave://")[1];
          path = "/" + cleanPath;
          codec = "arweave-ns";
          break;
        case (content.startsWith("bzz://")):
          cleanPath = content.split("bzz://")[1];
          path = "/bzz/" + cleanPath;
          codec = "swarm";
          break;
        default:
          return nullRecord();
      }
      break;
    default:
      return nullRecord()
  }
  return { codec, path };
}

function nullRecord() {
  return { path: "invalid", codec: 404 };
}

const codecToURIPrefixMap = {
  'skynet-ns': 'sia://',
  'ipfs-ns': 'ipfs://',
  'ipns-ns': 'ipns://',
  'arweave-ns': 'arweave://',
  'swarm': 'bzz://'
}

async function decodeContentHashContentHashLibraryFallback(data) {
  var cid = null
  try {
    cid = contentHash.decode(data)
    const codec = contentHash.getCodec(data)
    const prefix = codecToURIPrefixMap[codec]
    if (prefix !== undefined) {
      cid = `${prefix}${cid}`
    } else {
      logger.warn(`decodeContentHashContentHashLibraryFallback(): codec ${codec} is unrecognized`)
      return null
    }
  } catch (e) {
    logger.error('decodeContentHashContentHashLibraryFallback() ignoring error', e)
  }
  return cid
}

async function decodeContentHash0xe3Fallback(data) {
  const bytesData = ethers.utils.arrayify(data)
  if (bytesData[0] == 0xe3) {
    const data = bytesData.filter((_, i) => i > 1)
    const cid = `ipfs://${CID.parse(data, raw).toString()}`
    return cid
  } else {
    return null
  }
}

const fallbacks = {
  'decodeContentHashContentHashLibraryFallback': decodeContentHashContentHashLibraryFallback,
  'decodeContentHash0xe3Fallback': decodeContentHash0xe3Fallback,
}

async function decodeContentHashFallback(data) {
  logger.info(`decodeContentHashFallback(): beginning fallback resolution for ${data}`)
  var contentHash = null
  var resolver = ""
  for (const i of Object.keys(fallbacks)) {
    logger.info(`decodeContentHashFallback(): attempting fallback ${i}`)
    contentHash = await fallbacks[i](data)
    if (contentHash) {
      resolver = i
      break;
    }
  }

  if (contentHash === null) {
    logger.info(`decodeContentHashFallback(): failed to decode ${data}`)
  } else {
    logger.info(`decodeContentHashFallback(): successfully decoded ${data} -> ${contentHash} (${resolver})`)
  }
  return contentHash
}

async function lookupContentHash(res, hostname) {
  let contentHash = null;
  try {
    try {
      contentHash = await res.getContentHash();
    } catch (e) {
      if (e.reason === "invalid or unsupported content hash data" && e.operation === "getContentHash()") {
        contentHash = await decodeContentHashFallback(e.data)
        if (contentHash === null) {
          throw (e)
        }
      } else {
        throw (e)
      }
    }
    if (contentHash !== null) {
      let decodedRecord = parseRecord(contentHash, "contenthash");
      return decodedRecord;
    } else {
      return null
    }
  } catch (err) {
    logger.error(`Error retrieving contentHash from resolver for ${hostname}: `, err);
    return null;
  }
}


async function resolveEns(hostname) {
  let lock = await redlock.acquire([hostname + "-lock"], 15000);
  try {
    let cachedLookup = await checkCache(hostname);
    if (cachedLookup !== false) {
      return cachedLookup;
    } else {
      try {
        let res = await provider.getResolver(hostname);
        if (res != null) {
          let contentHash = await lookupContentHash(res, hostname);
          if (contentHash === null) {
            return nullRecord();
          } else {
            return contentHash
          }
        } else {
          return nullRecord();
        }
      } catch (err) {
        logger.error(`Unable to resolve ${hostname}: `, err);
        return nullRecord();
      }
    }
  } catch (err) {
    logger.error(`Error finding cache for ${hostname}: `, err);
    return nullRecord();
  } finally {
    await lock.release();
  }
}

module.exports = {
  resolveEns
}
