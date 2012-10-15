_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    secretToken: process.env.SECRET_TOKEN
    corsAllowedMethods: '*'
    corsAllowedHeaders: '*'
    corsAllowedOrigin: process.env.CORS_ALLOWED_ORIGIN
    socketIOAllowedOrigin: process.env.SOCKETIO_ALLOWED_ORIGIN
  development: {}
  test: {}
  staging:
    airbrakeKey: 'd38ce5cdc099322b5b78bfe2c6aafc60'
  production:
    airbrakeKey: 'c8b416de5a3a1467c8a5f2c204dcd321'

module.exports = _.extend settings.common, settings[env]
