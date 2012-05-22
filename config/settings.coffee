_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    secretToken: process.env.SECRET_TOKEN
  development: {}
  test: {}
  production: {}

module.exports = _.extend settings.common, settings[env]

