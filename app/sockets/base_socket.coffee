_ = require 'underscore'
cookie = require 'cookie'
User = require '../models/user'
metrics = require '../lib/metrics'

module.exports = class BaseSocket
  @EVENTS: []

  constructor: (@socket) ->
    @user = @socket.handshake.data.user
    events = _.chain(@constructor.EVENTS).union(['disconnect', 'bye']).uniq().value()
    for event in events
      fnName = 'on' + event[0].toUpperCase() + event.substring(1)
      @socket.on event, _.bind(this[fnName], this)

  onDisconnect: ->
    this.destroy()

  onBye: ->
    @socket?.disconnect()

  destroy: ->
    delete @socket.removeAllListeners()
    delete @socket
    delete @user

BaseSocket.create = (socket) ->
  new this(socket)

BaseSocket.init = (io, namespace) ->
  io.of(namespace)
    .authorization(this.authorize)
    .on 'connection', (socket) =>
      this.create(socket)

BaseSocket.authorize = (handshake, accept) ->
  unless handshake.headers.cookie
    accept('cookie missing', false)
    return
  data = handshake.data ||= {}
  data.cookies = cookie.parse handshake.headers.cookie
  User.verifyUserSession data.cookies['_aio_session'], (err, user) ->
    if err || !user
      metrics.increment 'user_session.invalid'
      accept('invalid user session', false)
      return
    data.user = user
    metrics.increment 'user_session.valid'
    accept(null, true)

