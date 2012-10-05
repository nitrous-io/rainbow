BaseSocket = require './base_socket'
Box = require '../models/box'
SFTP = require 'sftp.js'

module.exports = class SFTPSocket extends BaseSocket
  events: ['start', 'disconnect', 'ls', 'put', 'get']

  onStart: (boxId) ->
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
      box.findKeyPair (err, keyPair) =>
        if err
          @socket.emit 'start', err.toString()
          return
        unless keyPair
          @socket.emit 'start', 'key pair not found'
          return

        @sftp = new SFTP host: box.host, port: box.port, user: 'action', key: keyPair.private_key
        @sftp.connect (err) =>
          if err
            @socket.emit 'start', err.toString()
          else
            @socket.emit 'start'

  onDisconnect: ->
    super()

  onLs: ->

  onPut: ->

  onGet: ->

