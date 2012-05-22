process.env.NODE_ENV ?= 'development'

express = require 'express'
_ = require 'underscore'
pg = require('pg').native

app = express.createServer()
env = app.settings.env
_.extend app.settings, require './config/settings'

require('./config/application')(app)
require('./config/routes')(app)

database = require './config/database'
_.extend pg.defaults, database.postgres[env]

if require.main == module
  app.listen(process.env.PORT || 4000)
  if app.address()
    console.log "Action Box Server listening on port %d in %s mode", app.address().port, env
  else
    console.log 'Could not start Action Box Server!'

if env == 'production'
  process.on 'uncaughtException', (err) ->
    console.log err

module.exports = app

