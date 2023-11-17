const configuration = require('../configuration/config')

/**
 * 
 * @param {string} domain 
 * @returns {boolean}
 */
const checkIfDomainIsBlacklisted = (domain) => {
    if(!domain) {
        return false
    }
    for(const blockedHost of configuration.resolver.blacklist) {
        if(domain.length === blockedHost.length) {
            return blockedHost === domain
        } else {
            if(domain.endsWith(`.${blockedHost}`)) {
                return true
            }
        }
    }
    return false
}

module.exports = {
    checkIfDomainIsBlacklisted
}