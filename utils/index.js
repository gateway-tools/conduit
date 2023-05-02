const configuration = require('../configuration/config')

function getDomainOfRequestFromGet(req, param="domain") {
    let domain = req.query[param]
    let host = configuration.ask.host.join('.')
    if(domain.endsWith('.'+host)) {
        domain=domain.split('.'+host)[0]+'.eth'
    }
    if(domain.endsWith('.eth')) {
        return domain
    } else {
        return null
    }
}

//prerequisite: host in the form a.b.c.d, tld=1 <=> tld=d
function stripSubdomainsFromHost(host, tld=1) {
    if(host.length && host.length >= 2) {
        return host.split('.').slice(-1 - tld).join('.')
    } else {
        return null
    }
}

module.exports = {getDomainOfRequestFromGet, stripSubdomainsFromHost}