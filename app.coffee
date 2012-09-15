process.env.NODE_ENV ?= 'development'

_ = require 'underscore'

express = require 'express'
app = express()

# settings
env = app.settings.env
_.extend app.settings, require './config/settings'

# express config
require('./config/application')(app)

# postgres
pg = require('pg').native
database = require './config/database'
_.extend pg.defaults, database.postgres[env]

# routes
require('./config/routes')(app)

# logger
logger = require './app/lib/logger'

# uncaught exception handler
if env == 'production'
  process.on 'uncaughtException', (err) ->
    logger.error err

if require.main == module || require.main.filename.match /boot\.js/
  app.listen(process.env.PORT || 4000)
  unless app.address()
    logger.info 'Could not start Action Box Server!'
    return
  logger.info "Action Box Server listening on port %d in %s mode", app.address().port, env

  # socket.io
  socketIO = require 'socket.io'
  io = socketIO.listen(app)
  io.set 'log level', 1
  io.set 'match origin protocol', true
  require('./app/sockets/ssh_socket').init(io, '/ws/ssh')
  require('./app/sockets/fs_socket' ).init(io, '/ws/fs')

module.exports = app

