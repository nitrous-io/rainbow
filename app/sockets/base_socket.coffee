_ = require 'underscore'
cookie = require 'cookie'
User = require '../models/user'

module.exports = class BaseSocket
  constructor: (@socket) ->
    @user = @socket.handshake.data.user
    for event in @events
      fnName = 'on' + event[0].toUpperCase() + event.substring(1)
      @socket.on event, _.bind(this[fnName], this)

  events: ['disconnect']

  onDisconnect: ->
    this.destroy()

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
      accept('invalid user session', false)
      return
    data.user = user
    accept(null, true)

