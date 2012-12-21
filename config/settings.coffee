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
    redisStore:
      host: process.env.REDIS_STORE_HOST
      port: process.env.REDIS_STORE_PORT
      password: null
      database: 0
  development: {}
  test:
    redisStore:
      host: '0.0.0.0'
      port: 6379
      password: null
      database: 0
  staging: {}
  production: {}

module.exports = _.extend settings.common, settings[env]
