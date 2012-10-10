BaseSocket = require './base_socket'
Box = require '../models/box'
SFTP = require 'sftp.js'

module.exports = class SFTPSocket extends BaseSocket
  events: ['start', 'disconnect', 'list', 'read', 'write', 'writeNew']

  destroy: ->
    super()
    @sftp?.destroy()
    delete @sftp

  onStart: (boxId) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        @socket.emit 'start', err.toString()
        return
      unless box
        @socket.emit 'start', 'box not found'
        return
      if box.owner_id != @user.id
        @socket.emit 'start', "box doesn't belong to user"
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

  onList: (path) ->
    @sftp?.ls path, (err, fileListing) =>
      @socket.emit 'list', err?.toString(), path, fileListing

  onRead: (path) ->
    @sftp?.get path, (err, fileBuffer) =>
      @socket.emit 'read', err?.toString(), path, fileBuffer?.toString('utf8')

  onWrite: (path, content, overwrite=true) ->
    return unless @sftp
    putFile = =>
      @sftp.put path, content, (err) =>
        @socket.emit 'write', err?.toString(), path

    if overwrite
      putFile()
    else
      @sftp.ls path, (err) =>
        if err
          if err.match /\" not found$/
            putFile()
          else
            @socket.emit 'write', err, path
        else
          @socket.emit 'write', 'file exists', path

  onWriteNew: ->

