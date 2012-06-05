aio = require '../lib/aio'
parseCookie = require('connect').utils.parseCookie
User = require '../models/user'
Box = require '../models/box'
SSHHelper = require '../lib/ssh_helper'
pty = require 'pty.js'

module.exports = class SSHSocket
  constructor: (@socket) ->
    @user = @socket.handshake.data.user
    @socket.on 'start', this.onStart
    @socket.on 'd', this.onData
    @socket.on 'r', this.onResize
    @socket.on 'kill', this.onKill
    @socket.on 'disconnect', this.onDisconnect

  onStart: (boxId) =>
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        @socket.emit('start', err.toString())
        return
      unless box
        @socket.emit('start', 'box not found')
        return
      if box.owner_id != @user.id
        @socket.emit('start', "box doesn't belong to user")
        return
      if @pty
        @socket.emit('start', 'pty already created')
        return
      @box = box
      this.connectToSSH (err) =>
        if err
          @socket.emit('start', err.toString())
          return
        @socket.emit('start')

  connectToSSH: (callback) ->
    @box.findKeyPair (err, keyPair) =>
      if err
        callback(err)
        return
      unless keyPair
        callback('key pair not found')
        return

      sshHelper = new SSHHelper('action', @box.host, @box.port, keyPair.private_key)
      sshHelper.writeKeyFile (err, sshArgs, deleteKeyFile) =>
        if err
          callback(err)
          return
        @pty = pty.spawn '/usr/bin/ssh', sshArgs
        @pty.once 'data', ->
          deleteKeyFile()
        @pty.on 'data', this.onPTYData
        @pty.on 'close', this.onPTYClose
        callback(null)

  onData: (data) =>
    return unless @pty
    @pty.write(data)

  onResize: (width, height) =>
    return unless @pty
    @pty.resize(width, height)

  onKill: =>
    return unless @pty
    @pty.destroy()
    delete @pty

  onDisconnect: =>
    this.onKill()
    delete @socket
    delete @box
    delete @user

  onPTYData: (data) =>
    @socket?.emit('d', data)

  onPTYClose: (hadError) =>
    delete @pty
    @socket?.emit('close')

SSHSocket.create = (socket) ->
  new SSHSocket(socket)

SSHSocket.init = (io) ->
  io.of('/ws/ssh')
    .authorization(SSHSocket.authorize)
    .on 'connection', (socket) ->
      SSHSocket.create(socket)

SSHSocket.authorize = (handshake, accept) ->
  unless handshake.headers.cookie
    accept('cookie missing', false)
    return
  data = handshake.data ||= {}
  data.cookies = parseCookie(handshake.headers.cookie)
  User.verifyUserSession data.cookies['_aio_session'], (err, user) ->
    if err || !user
      accept('invalid user session', false)
      return
    data.user = user
    accept(null, true)

