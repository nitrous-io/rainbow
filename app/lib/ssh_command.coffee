fs = require 'fs'
tmp = require 'tmp'
childProcess = require 'child_process'

module.exports = class SSHCommand
  constructor: (@user, @host, @port, @key) ->

  exec: (command, callback) ->
    tmp.file (err, path, fd) =>
      if err
        callback(err)
        return
      b = new Buffer(@key)
      fs.write fd, b, 0, b.length, 0, (err, written, buffer) =>
        if err
          fs.unlink path, -> callback(err)
          return
        args = [
          'ssh'
          '-i', path
          '-o', 'UserKnownHostsFile=/dev/null'
          '-o', 'StrictHostKeyChecking=no'
          '-o', 'PubkeyAuthentication=yes'
          '-o', 'PasswordAuthentication=no'
          '-p', "#{@port}"
          "#{@user}@#{@host}"
          command
        ]
        childProcess.execFile '/usr/bin/env', args, timeout: 20000, (err, stdout, stderr) ->
          fs.unlink path, ->
            callback(err, stdout, stderr)

