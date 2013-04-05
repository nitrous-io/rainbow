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
AuthTokenVerifier = require './app/lib/auth_token_verifier'
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

# send uptime/memory usage data to statsd
(new Repoman).collect()

logger = require './app/lib/logger'

if require.main == module || require.main.filename.match /boot\.js/
  server = http.createServer app

  # sockjs
  SocketConnection = require './app/lib/socket_connection'
  socks = require './app/socks'

  app.sock = sock = sockjs.createServer
    sockjs_url: 'http://cdn.sockjs.org/sockjs-0.3.min.js'

  sock.on 'connection', (ws) ->
    sc = new SocketConnection(ws, app)
    sc.register socks.SSHSock
    sc.register socks.SFTPSock

  sock.installHandlers server, prefix: '/sock'

  server.listen(process.env.PORT || 4000)
  unless address = server.address()
    logger.info 'Could not start Rainbow!'
    return

  logger.info "Rainbow listening on port #{address.port} in #{env} mode"

