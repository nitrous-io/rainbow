BaseSocket = require './base_socket'
Box = require '../models/box'
SFTP = require 'sftp.js'

module.exports = class SFTPSocket extends BaseSocket
  events: ['start', 'list', 'read', 'write', 'writeNew']

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

  putFile: (eventName, path, content) ->
    @sftp.put path, content, (err) =>
      @socket.emit eventName, err?.toString(), path

  onWrite: (path, content) ->
    return unless @sftp
    this.putFile 'write', path, content

  onWriteNew: (path, content) ->
    return unless @sftp
    @sftp.ls path, (err) =>
      if err
        if err.match /Can't ls: ".+" not found$/
          this.putFile 'writeNew', path, content
        else
          @socket.emit 'writeNew', err, path
      else
        @socket.emit 'writeNew', 'file exists', path

