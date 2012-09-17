process.env.NODE_ENV ?= 'development'

_ = require 'underscore'
settings = require './config/settings'
logger = require './app/lib/logger'

express = require 'express'
app = express()

# settings
env = app.settings.env
_.extend app.settings, settings

# express config
require('./config/application')(app)

# postgres
pg = require('pg').native
database = require './config/database'
_.extend pg.defaults, database.postgres[env]

# routes
require('./config/routes')(app)

# uncaught exception handler
if env == 'production'
  process.on 'uncaughtException', (err) ->
    logger.error err

if require.main == module || require.main.filename.match /boot\.js/
  server = app.listen(process.env.PORT || 4000)
  unless address = server.address()
    logger.info 'Could not start Action Box Server!'
    return

  logger.info "Action Box Server listening on port #{address.port} in #{env} mode"

  # socket.io
  socketIO = require 'socket.io'
  io = socketIO.listen(server)
  io.set 'log level', if env == 'development' then 3 else 1
  io.set 'match origin protocol', true
  require('./app/sockets/ssh_socket').init(io, '/ws/ssh')
  require('./app/sockets/fs_socket' ).init(io, '/ws/fs')

module.exports = app

