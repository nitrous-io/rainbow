BaseSocket = require './base_socket'
Box = require '../models/box'
SFTP = require 'sftp.js'
fs = require 'fs'
app = require '../../app'

module.exports = class SFTPSocket extends BaseSocket
  @SIZE_LIMIT: 2 * 1024 * 1024 # 2 megabytes
  @EVENTS: ['start', 'list', 'read', 'write', 'writeNew', 'makeDir', 'upload']

  destroy: ->
    super()
    @sftp?.destroy()
    delete @sftp

  onStart: (boxId, ack) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        ack? err.toString()
        return
      unless box
        ack? 'box not found'
        return
      if box.owner_id != @user.id
        ack? "box doesn't belong to user"
        return
      box.findKeyPair (err, keyPair) =>
        if err
          ack? err.toString()
          return
        unless keyPair
          ack? 'key pair not found'
          return

        @sftp = new SFTP host: box.host, port: box.port, user: 'action', key: keyPair.private_key
        @sftp.connect (err) =>
          if err
            ack? err.toString()
          else
            ack?()

  onList: (path, ack) ->
    @sftp?.ls path, (err, fileListing) =>
      ack? err?.toString(), path, fileListing

  onRead: (path, ack) ->
    return unless @sftp
    @sftp.ls path, (err, list) =>
      if err
        ack? err.toString(), path
      else
        if list[0] && list[0][2] <= @constructor.SIZE_LIMIT
          @sftp.get path, (err, fileBuffer, fileType) =>
            if err
              ack? err.toString(), path
            else
              if fileType.match /text|very short|empty/
                ack? null, path, fileBuffer?.toString('utf8')
              else
                ack? 'aio:not_text_file', path
        else
          ack? 'aio:file_too_large', path

  putFile: (path, content, ack) ->
    @sftp.putData path, content, (err) =>
      ack? err?.toString(), path

  onWrite: (path, content, ack) ->
    return unless @sftp
    this.putFile path, content, ack

  checkIfPathExists: (path, callback) ->
    @sftp.ls path, (err) =>
      if err
        if err.toString().match /Can't ls: ".+" not found$/
          callback false
        else
          callback err.toString()
      else
        callback true

  onWriteNew: (path, content, ack) ->
    return unless @sftp
    this.checkIfPathExists path, (exists) =>
      unless exists
        this.putFile path, content, ack
      else if exists == true
        ack? 'aio:file_exists', path
      else # some random error
        ack? exists, path

  onMakeDir: (path, ack) ->
    return unless @sftp
    this.checkIfPathExists path, (exists) =>
      unless exists
        @sftp.mkdir path, (err) =>
          ack? err?.toString(), path
      else if exists == true
        ack? 'aio:dir_exists', path
      else # some random error
        ack? exists, path

  onUpload: (path, uploadToken, ack) ->
    return unless @sftp
    upload = app.messageVerifier.verify uploadToken
    if upload && upload.tmpFilePath
      @sftp.put upload.tmpFilePath, path, (err) =>
        fs.unlink upload.tmpFilePath
        ack? err?.toString(), path
    else
      ack? 'invalid upload token', path

