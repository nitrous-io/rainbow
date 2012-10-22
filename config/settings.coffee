_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    secretToken: process.env.SECRET_TOKEN
    corsAllowedMethods: '*'
    corsAllowedHeaders: '*'
  development:
    corsAllowedOrigin: 'https://dev.action.io:5000'
  test:
    corsAllowedOrigin: 'https://www.action.io'
  production:
    corsAllowedOrigin: 'https://www.action.io https://staging.action.io'

module.exports = _.extend settings.common, settings[env]

