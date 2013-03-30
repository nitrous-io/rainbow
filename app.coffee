process.env.NODE_ENV ?= 'development'
process.title = "rainbow"

express = require 'express'
module.exports = app = express()

http       = require 'http'
_          = require 'underscore'
pg         = require('pg').native
airbrake   = require 'airbrake'
actionBase = require 'action-base'
Repoman    = require 'repoman'
socketIO   = require 'socket.io'
sockjs     = require 'sockjs'

# settings
settings = require './config/settings'
env = app.settings.env
_.extend app.settings, settings

# express config
require('./config/application')(app)

# message verifier
MessageVerifier = actionBase.MessageVerifier
app.messageVerifier = new MessageVerifier app.settings.secretToken

# postgres
database = require './config/database'
_.extend pg.defaults, database.postgres[env]

# routes
require('./config/routes')(app)

if app.settings.airbrakeAPIKey
  ab = airbrake.createClient app.settings.airbrakeAPIKey
  ab.handleExceptions() # Don't die when an exception occurs
else
  process.on 'uncaughtException', (err) ->
    console.log err
    console.log err.message
    console.log err.stack

# send uptime/memory usage data to statsd
(new Repoman).collect()

logger = require './app/lib/logger'

if require.main == module || require.main.filename.match /boot\.js/
  server = http.createServer app

  # socket.io
  app.io = io = socketIO.listen(server)
  io.configure ->
    io.enable 'log'
    io.set 'origins', settings.socketIOAllowedOrigin
    io.set 'log level', if env == 'development' then 3 else 1
    io.set 'transports', ['websocket']
    io.set 'match origin protocol', true
  require('./app/sockets/ssh_socket').init io, '/ws/ssh'
  require('./app/sockets/sftp_socket' ).init io, '/ws/sftp'

  # sockjs
  SocketConnection = require './app/lib/socket_connection'
  SSHSock = require './app/socks/ssh_sock'

  app.sock = sock = sockjs.createServer
    sockjs_url: 'http://cdn.sockjs.org/sockjs-0.3.min.js'

  sock.on 'connection', (ws) ->
    sc = new SocketConnection(ws)
    sc.register SSHSock

  sock.installHandlers server, prefix: '/sock'

  server.listen(process.env.PORT || 4000)
  unless address = server.address()
    logger.info 'Could not start Rainbow!'
    return

  logger.info "Rainbow listening on port #{address.port} in #{env} mode"

