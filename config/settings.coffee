_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    secretToken: process.env.SECRET_TOKEN
    corsAllowedMethods: '*'
    corsAllowedHeaders: '*'
    corsAllowedOrigin: process.env.CORS_ALLOWED_ORIGIN
    socketIOAllowedOrigin: process.env.SOCKETIO_ALLOWED_ORIGIN

module.exports = _.extend settings.common, settings[env]

