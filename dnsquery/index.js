const logger = require("../logging/log");
const { errorBuilder, blockedForLegalReasons } = require("../expressErrors")
const dnsPacket = require('dns-packet');
const configuration = require("../configuration/config");
const ens = require('../ens/ens')
const { updateCache, checkCache } = require("../cache/redis");
const { checkIfDomainIsBlacklisted } = require('../blacklist')
const logHeaderError = (header, req) => {
    const val = req.header(header)
    logger.error(`dnsqueryPost: unexpected header ${header}=${val}`)
}


const handleDnsQuery = async (dnsRequest) => {
    var responses = []
    if (dnsRequest.questions.length > 5) {
        return {
            error: true,
            code: 400,
            message: "Too many questions"
        }
    }
    for (var question of dnsRequest.questions) {
        if (question.type.toLowerCase() !== 'txt' || !question.name.endsWith('.eth')) {
            logger.info(`handleDnsQuery: ignoring question ${question.name} (${question.type})`)
            continue
        }
        logger.info(`handleDnsQuery: Processing request for ${question.name}`)
        var dohDomain
        if (question.name.startsWith('_dnslink.')) {
            dohDomain = question.name.split('_dnslink.')[1]
            logger.info(`handled dnslink prefix for ${dohDomain}`)
        } else {
            dohDomain = question.name
        }
        let isCached = await checkCache(dohDomain);
        if (isCached === false) {
            result = await ens.resolveEns(dohDomain)
            await updateCache(dohDomain, result);
        } else {
            result = isCached;
        }
        var temp = {
            type: 'TXT',
            class: 'IN',
            name: question.name,
            ttl: configuration.cache.ttl,
        }
        var found = false
        if (result.codec === 'ipfs-ns' || result.codec == 'ipns-ns') {
            found = true
            temp.data = `dnslink=${result.path}`
        } else if (result.codec == 'skynet-ns') {
            found = true
            temp.data = `dnslink=/skynet-ns${result.path}`
        }
        if (found) {
            logger.info(`handleDnsQuery: response to question ${question.name} (${question.type}) ${temp.data} (codec: ${result.codec})`)
            responses.push(temp)
        }
        else {
            logger.error(`handleDnsQuery: Unresolved codec query ${result.codec} in dnsquery`)
        }
    }

    try {
        const responsePacket = dnsPacket.encode({
            id: dnsPacket.id,
            type: 'response',
            questions: dnsRequest.questions,
            answers: responses
        })

        return {
            payload: true,
            data: responsePacket
        }


    } catch (e) {
        logger.error('When building dns response packet', e)
        return {
            error: true,
            code: 500,
            message: "Internal server error"
        }
    }
}


const dnsqueryPost = async (req, res) => {
    if (req.header('accept') !== 'application/dns-message') {
        logHeaderError('accept', req)
        errorBuilder(res, 415)
        return
    }

    if (req.header('content-type') !== 'application/dns-message') {
        logHeaderError('content-type', req)
        errorBuilder(res, 415)
        return
    }

    const requestBody = req.body
    let dnsRequest
    try {
        dnsRequest = dnsPacket.decode(requestBody)
    } catch (e) {
        logger.error('dnsqueryPost: could not decode DNS packet', e)
        errorBuilder(res, 500)
        return
    }

    if (dnsRequest.questions) {
        for (const question of dnsRequest.questions) {
            if (checkIfDomainIsBlacklisted(question.name)) {
                blockedForLegalReasons(res)
                return
            }
        }
    }

    const responsePacket = await handleDnsQuery(dnsRequest)
    if (responsePacket.payload) {
        if (responsePacket.error) {
            errorBuilder(res, responsePacket.code)
            return
        }
        const data = new Uint8Array(responsePacket.data)
        res.writeHead(200, {
            'Content-Type': 'application/dns-message'
        });
        res.write(data)
        res.end()
    }
}

const dnsqueryGet = async (req, res) => {
    let dnsRequest
    if (req.query.dns) {
        const query = Buffer.from(req.query.dns, 'base64url')
        if (query.length > 512) {
            errorBuilder(res, 413)
            return
        }
        try {
            dnsRequest = dnsPacket.decode(query)
        } catch (e) {
            logger.error('dnsqueryGet: could not decode DNS packet', e)
            errorBuilder(res, 500)
            return
        }
    } else {
        let tmp = {
            id: 0,
            type: 'query',
            flags: 256,
            flag_qr: false,
            flag_aa: false,
            flag_tc: false,
            flag_rd: true,
            flag_ra: false,
            flag_z: false,
            flag_ad: false,
            flag_cd: false,
            rcode: 'NOERROR',
            questions: [],
            answers: [],
            authorities: [],
            additionals: [],
        }
        if (!req.query || !req.query.name) {
            errorBuilder(res, 400)
            return
        }


        //TODO: is this already punycoded? how does it behave with utf8?
        //TODO: from the docs, RFC 4343 backslash escapes are accepted
        //not clear on how to unescape this
        var name = req.query.name
        if (name.length > 253 || name.length < 1) {
            errorBuilder(res, 400)
            return
        }
        //default to TXT type
        var type = req.query.type ?? "16"
        if (type === "16") {
            type = "TXT"
        }
        var q = {
            name,
            type
        }
        tmp.questions.push(q)
        dnsRequest = tmp
    }
    if (dnsRequest.questions) {
        for (const question of dnsRequest.questions) {
            if(checkIfDomainIsBlacklisted(question.name)) {
                blockedForLegalReasons(res)
                return
            }
        }
    }

    const result = await handleDnsQuery(dnsRequest)
    if (result.payload) {

        const data = result.data
        if (req.query.ct === "application/dns-message" || (req.query.dns && !req.query.ct)) {
            res.writeHead(200, {
                'Content-Type': 'application/dns-message'
            });
            res.write(data)
            res.end()

        } else {
            const decoded = dnsPacket.decode(data)
            const ret = {
                Status: "0",
                RD: decoded.flag_rd,
                RA: decoded.flag_ra,
                AD: decoded.flag_ad,
                CD: decoded.flag_cd,
                TC: false,
                Question: [],
                Answer: [],
            }
            if (decoded.questions) {
                for (var q of decoded.questions) {
                    var tmp = {

                    }
                    //we only know how to handle txt
                    if (q.type.toLowerCase() === 'txt') {
                        tmp.type = 16
                    } else {
                        logger.error(`dnsqueryGet: unhandled question type ${q.type}`)
                        continue
                    }
                    tmp.name = q.name
                    ret.Question.push(tmp)
                }
            }
            if (decoded.answers) {
                for (var a of decoded.answers) {
                    var tmp = {
                    }
                    //we only know how to handle txt
                    if (q.type.toLowerCase() === 'txt') {
                        tmp.type = 16
                    } else {
                        logger.error(`dnsqueryGet: unhandled question type ${q.type}`)
                        continue
                    }
                    tmp.name = a.name,
                        tmp.data = a.data.toString()
                    tmp.ttl = Number(configuration.cache.ttl)
                    ret.Answer.push(tmp)
                }
            }
            res.writeHead(200, {
                'Content-Type': 'application/x-javascript'
            });
            res.write(JSON.stringify(ret))
            res.end()
        }

    } else {
        errorBuilder(res, result.code || 500)
        return
    }
}

module.exports = {
    dnsqueryPost,
    dnsqueryGet
}
