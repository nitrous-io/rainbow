_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    aesKey: process.env.AES_KEY
    secretToken: process.env.SECRET_TOKEN
    corsAllowedMethods: '*'
    corsAllowedHeaders: '*'
    corsAllowedOrigin: process.env.CORS_ALLOWED_ORIGIN
    socketIOAllowedOrigin: process.env.SOCKETIO_ALLOWED_ORIGIN
    airbrakeAPIKey: process.env.AIRBRAKE_API_KEY
  development: {}
  test: {}
  staging: {}
  production: {}

module.exports = _.extend settings.common, settings[env]
