process.env.NODE_ENV ?= 'development'
process.title = "rainbox"

express = require 'express'
module.exports = app = express()

_ = require 'underscore'

# settings
settings = require './config/settings'
env = app.settings.env
_.extend app.settings, settings

# express config
require('./config/application')(app)

# message verifier
MessageVerifier = require('action-base').MessageVerifier
app.messageVerifier = new MessageVerifier app.settings.secretToken

# postgres
pg = require('pg').native
database = require './config/database'
_.extend pg.defaults, database.postgres[env]

# routes
require('./config/routes')(app)

if app.settings.airbrakeAPIKey
  airbrake = require('airbrake').createClient app.settings.airbrakeAPIKey
  airbrake.handleExceptions()
else
  process.on 'uncaughtException', (err) ->
    console.log err
    console.log err.message
    console.log err.stack

# send uptime/memory usage data to statsd
Repoman = require('repoman')
(new Repoman).collect()

logger = require './app/lib/logger'
if require.main == module || require.main.filename.match /boot\.js/
  server = app.listen(process.env.PORT || 4000)
  unless address = server.address()
    logger.info 'Could not start Rainbow!'
    return

  logger.info "Rainbow listening on port #{address.port} in #{env} mode"

  # socket.io
  socketIO = require 'socket.io'
  app.io = io = socketIO.listen(server)
  io.configure ->
    io.enable 'log'
    io.set 'origins', settings.socketIOAllowedOrigin
    io.set 'log level', if env == 'development' then 3 else 1
    io.set 'transports', ['websocket']
    io.set 'match origin protocol', true
  require('./app/sockets/ssh_socket').init io, '/ws/ssh'
  require('./app/sockets/sftp_socket' ).init io, '/ws/sftp'
