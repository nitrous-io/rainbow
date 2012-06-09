process.env.NODE_ENV ?= 'development'

_ = require 'underscore'

express = require 'express'
app = express.createServer()

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

# uncaught exception handler
if env == 'production'
  process.on 'uncaughtException', (err) ->
    console.log err

if require.main == module || require.main.filename.match /boot\.js/
  app.listen(process.env.PORT || 4000)
  unless app.address()
    console.log 'Could not start Action Box Server!'
    return
  console.log "Action Box Server listening on port %d in %s mode", app.address().port, env

  # socket.io
  socketIO = require 'socket.io'
  io = socketIO.listen(app)
  io.set 'log level', 1
  require('./app/sockets/ssh_socket').init(io, '/ws/ssh')

module.exports = app

