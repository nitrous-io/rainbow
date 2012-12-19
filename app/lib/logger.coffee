winston = require 'winston'
env = process.env.NODE_ENV

config =
  levels:
    info: 2
    warn: 5
    debug: 5
    error: 6
  colors:
    info: 'green'
    warn: 'yellow'
    debug: 'blue'
    error: 'red'

module.exports = logger = new winston.Logger
  transports: [
    new winston.transports.Console colorize: true
    new winston.transports.File
      filename: "log/rainbow.log"
      json: false
      timestamp: true
      handleExceptions: true
  ],
  levels: config.levels
  colors: config.colors

