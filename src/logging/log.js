const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  defaultMeta: { service: 'conduit' },
});

logger.add(new winston.transports.Console({
  format: winston.format.json(),
}));

module.exports = logger;