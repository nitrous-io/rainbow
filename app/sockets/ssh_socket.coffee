BaseSocket = require './base_socket'
Box = require '../models/box'
SSHHelper = require '../lib/ssh_helper'
pty = require 'pty.js'

module.exports = class SSHSocket extends BaseSocket
  constructor: (@socket) ->
    super(@socket)
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
    @box?.findKeyPair (err, keyPair) =>
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
        try
          @pty = pty.spawn '/usr/bin/ssh', sshArgs
        catch err
          deleteKeyFile ->
            callback(err)
          return
        @pty.once 'data', ->
          deleteKeyFile()
        @pty.on 'data', this.onPTYData
        @pty.on 'close', this.onPTYClose
        callback(null)

  onData: (data) =>
    @pty?.write(data)

  onResize: (width, height) =>
    @pty?.resize(width, height)

  onKill: =>
    @pty?.destroy()
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

