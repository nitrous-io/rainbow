BaseSocket = require './base_socket'
Box = require '../models/box'
SFTP = require 'sftp.js'
fs = require 'fs'
app = require '../../app'

module.exports = class SFTPSocket extends BaseSocket
  @SIZE_LIMIT: 2 * 1024 * 1024 # 2 megabytes
  @EVENTS: ['start', 'list', 'read', 'write', 'writeNew', 'upload']

  destroy: ->
    super()
    @sftp?.destroy()
    delete @sftp

  onStart: (boxId) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        @socket.emit 'ack-start', err.toString()
        return
      unless box
        @socket.emit 'ack-start', 'box not found'
        return
      if box.owner_id != @user.id
        @socket.emit 'ack-start', "box doesn't belong to user"
        return
      box.findKeyPair (err, keyPair) =>
        if err
          @socket.emit 'ack-start', err.toString()
          return
        unless keyPair
          @socket.emit 'ack-start', 'key pair not found'
          return

        @sftp = new SFTP host: box.host, port: box.port, user: 'action', key: keyPair.private_key
        @sftp.connect (err) =>
          if err
            @socket.emit 'ack-start', err.toString()
          else
            @socket.emit 'ack-start'

  onList: (path) ->
    @sftp?.ls path, (err, fileListing) =>
      @socket.emit 'ack-list', err?.toString(), path, fileListing

  onRead: (path) ->
    return unless @sftp
    @sftp.ls path, (err, list) =>
      if err
        @socket.emit 'ack-read', err.toString(), path
      else
        if list[0] && list[0][2] <= @constructor.SIZE_LIMIT
          @sftp.get path, (err, fileBuffer, fileType) =>
            if err
              @socket.emit 'ack-read', err.toString(), path
            else
              if fileType.match /text|very short|empty/
                @socket.emit 'ack-read', null, path, fileBuffer?.toString('utf8')
              else
                @socket.emit 'ack-read', 'aio:not_text_file', path
        else
          @socket.emit 'ack-read', 'aio:file_too_large', path

  putFile: (eventName, path, content) ->
    @sftp.putData path, content, (err) =>
      @socket.emit eventName, err?.toString(), path

  onWrite: (path, content) ->
    return unless @sftp
    this.putFile 'ack-write', path, content

  onWriteNew: (path, content) ->
    return unless @sftp
    @sftp.ls path, (err) =>
      if err
        if err.toString().match /Can't ls: ".+" not found$/
          this.putFile 'ack-writeNew', path, content
        else
          @socket.emit 'ack-writeNew', err.toString(), path
      else
        @socket.emit 'ack-writeNew', 'aio:file_exists', path

  onUpload: (path, uploadToken) ->
    return unless @sftp
    upload = app.messageVerifier.verify uploadToken
    if upload && upload.tmpFilePath
      @sftp.put upload.tmpFilePath, path, (err) =>
        fs.unlink upload.tmpFilePath
        @socket.emit 'ack-upload', err?.toString(), path
    else
      @socket.emit 'ack-upload', 'invalid upload token', path

