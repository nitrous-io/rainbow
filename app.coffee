process.env.NODE_ENV ?= 'development'
process.title = "rainbow"

express = require 'express'
module.exports = app = express()

http       = require 'http'
_          = require 'underscore'
pg         = require('pg').native
airbrake   = require 'airbrake'
actionBase = require 'action-base'
sockjs     = require 'sockjs'
Ping       = require 'ping'

# settings
settings = require './config/settings'
env = app.settings.env
_.extend app.settings, settings

# express config
require('./config/application')(app)

# message verifier
MessageVerifier = actionBase.MessageVerifier
AuthTokenVerifier = actionBase.AuthTokenVerifier
app.messageVerifier = new MessageVerifier app.settings.secretToken
app.authTokenVerifier = new AuthTokenVerifier 'rainbow', app.messageVerifier

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

if require.main == module || require.main.filename.match /boot\.js/
  server = http.createServer app

  # sockjs
  SocketConnection = actionBase.SocketConnection
  sockets = require './app/sockets'

  app.sock = sock = sockjs.createServer
    sockjs_url: 'http://cdn.sockjs.org/sockjs-0.3.min.js'

  sock.on 'connection', (ws) ->
    sc = new SocketConnection(ws, app.authTokenVerifier)
    sc.register sockets.SSHSocket
    sc.register sockets.SFTPSocket
    sc.register sockets.PartsSocket

  sock.installHandlers server, prefix: '/ws'

  server.listen(process.env.PORT || 4000)
  unless address = server.address()
    console.error 'Could not start Rainbow!'
    return

  # This is a server that will be used by monitoring services (such as Datadog, etc.)
  # to ping to see if Rainbow is up
  pingServer = new Ping
    checkFunction: (cb) ->
      actionBase.BaseModel.testConnection (err) ->
        cb err

  pingServer.start()

  console.log "Rainbow listening on port #{address.port} in #{env} mode"
