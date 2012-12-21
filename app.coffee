process.env.NODE_ENV ?= 'development'

express = require 'express'
redis   = require 'redis'
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

logger = require './app/lib/logger'

# create a redis client based on settings configuration. Refers to
# `config/settings.coffee` for the supported settings
createRedisClient = (settings) ->
  return unless settings
  client = redis.createClient settings.port, settings.host
  client.auth settings.password if settings.password
  client.select settings.database
  client

if require.main == module || require.main.filename.match /boot\.js/
  # socket.io
  socketIO = require 'socket.io'
  http = require 'http'
  RedisStore = require 'socket.io/lib/stores/redis'
  server = http.createServer(app)
  io = socketIO.listen(server)

  io.configure ->
    # create redis client for socket.io
    pub = createRedisClient app.settings.redisStore
    sub = createRedisClient app.settings.redisStore
    client = createRedisClient app.settings.redisStore

    io.enable 'log'
    io.set 'origins', settings.socketIOAllowedOrigin
    io.set 'log level', if env == 'development' then 3 else 1
    io.set 'transports', ['websocket']
    io.set 'match origin protocol', true
    io.set 'store', new RedisStore(redisPub: pub, redisSub: sub, redisClient: client)

  require('./app/sockets/ssh_socket').init io, '/ws/ssh'
  require('./app/sockets/sftp_socket' ).init io, '/ws/sftp'

  # bootstrap cluster2
  Cluster = require 'cluster2'
  cluster = new Cluster
    port: (process.env.PORT || 4000)
    monHost: app.settings.monHost
    monPort: app.settings.monPort

  cluster.on 'died', (pid) ->
    logger.info "Rainbow worker #{pid} died"
  cluster.on 'forked', (pid) ->
    logger.info "Rainbow worker #{pid} forked"
  cluster.on 'SIGKILL', ->
    logger.info "Rainbow got SIGKILL"
  cluster.on 'SIGTERM', ->
    logger.info "Rainbow got SIGTERM - shutting down"
  cluster.on 'SIGINT', ->
    logger.info "Rainbow got SIGINT"

  cluster.listen (cb) ->
    cb server
