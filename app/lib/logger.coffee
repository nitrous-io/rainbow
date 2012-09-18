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

logger = module.exports = new winston.Logger
                                        transports: [
                                          new winston.transports.Console colorize: true
                                          new winston.transports.File
                                                                    filename: "log/#{env}.log"
                                                                    json: false
                                                                    maxsize: 5 * 1024 * 1024
                                                                    timestamp: true
                                                                    handleExceptions: true
                                        ],
                                        levels: config.levels
                                        colors: config.colors

