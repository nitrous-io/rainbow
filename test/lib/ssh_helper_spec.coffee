SSHHelper = require '../../app/lib/ssh_helper'
fs = require 'fs'
tmp = require 'tmp'
childProcess = require 'child_process'

describe 'SSHHelper', ->
  sshHelper = null

  beforeEach ->
    sshHelper = new SSHHelper('peter', 'localhost', '2222', 'ssh-rsa AAAB3NzaC1yc2EAAA peter@kim')

  describe '#writeKeyFile', ->
    err = cbSpy = null

    context 'when temp file failed to get created', ->
      beforeEach ->
        err = new Error
        sinon.stub tmp, 'file', (cb) ->
          cb(err)
        cbSpy = sinon.spy()
        sshHelper.writeKeyFile(cbSpy)

      afterEach ->
        tmp.file.restore()

      it 'makes a callback with the error', ->
        cbSpy.calledWith(err).should.be.true

    context 'when temp file is successfully created', ->
      fakeFd = null

      beforeEach ->
        err = new Error
        fakeFd = {}
        sinon.stub tmp, 'file', (cb) ->
          cb(null, '/tmp/tmpfile', fakeFd)
        sinon.stub fs, 'unlink', (path, cb) ->
          cb()

      afterEach ->
        tmp.file.restore()
        fs.unlink.restore()

      context 'when the key failed to be written to the temp file', ->
        beforeEach ->
          fs.write = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            fd.should.equal fakeFd
            cb(err)
          cbSpy = sinon.spy()
          sshHelper.writeKeyFile(cbSpy)
          fs.write.called.should.be.true

        afterEach ->
          fs.write.restore()

        it 'deletes the temp file', ->
          fs.unlink.called.should.be.true
          fs.unlink.args[0][0].should.equal '/tmp/tmpfile'

        it 'makes a callback with the error', ->
          cbSpy.calledWith(err).should.be.true

      context 'when the key is successfully written to the temp file', ->
        beforeEach ->
          fs.write = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            fd.should.equal fakeFd
            cb()
          cbSpy = sinon.spy()
          sshHelper.writeKeyFile(cbSpy)
          fs.write.called.should.be.true

        afterEach ->
          fs.write.restore()

        it 'makes a callback with ssh arguments as the first argument', ->
          cbSpy.called.should.be.true
          sshArgs = cbSpy.args[0][1].join(' ')
          sshArgs.should.match /^-i \/tmp\/tmpfile/
          sshArgs.should.match /-o UserKnownHostsFile=\/dev\/null/
          sshArgs.should.match /-o StrictHostKeyChecking=no/
          sshArgs.should.match /-o PubkeyAuthentication=yes/
          sshArgs.should.match /-o PasswordAuthentication=no/
          sshArgs.should.match /-o LogLevel=FATAL/
          sshArgs.should.match /-p 2222/
          sshArgs.should.match /peter@localhost/

        describe 'deleteKeyFile function', ->
          context 'with a callback', ->
            it 'deletes the temp key file and then calls the callback', (done) ->
              cbSpy.called.should.be.true
              cbSpy.args[0][2] ->
                fs.unlink.called.should.be.true
                fs.unlink.args[0][0].should.equal '/tmp/tmpfile'
                done()

          context 'without a callback', ->
            it 'deletes the temp key file', ->
              cbSpy.called.should.be.true
              cbSpy.args[0][2]()
              fs.unlink.called.should.be.true
              fs.unlink.args[0][0].should.equal '/tmp/tmpfile'

  describe '#execCommand', ->
    err = cbSpy = null

    context 'when writeKeyFile fails with error', ->
      beforeEach ->
        err = new Error
        cbSpy = sinon.spy()
        sinon.stub sshHelper, 'writeKeyFile', (callback) ->
          callback(err)
        sshHelper.execCommand('ls', cbSpy)
        sshHelper.writeKeyFile.called.should.be.true

      it 'makes a callback with the error', ->
        cbSpy.calledWith(err).should.be.true

    context 'when writeKeyFile succeeds', ->
      deleteKeyFileSpy = null

      beforeEach ->
        deleteKeyFileSpy = sinon.spy (cb) -> cb()
        cbSpy = sinon.spy()
        sinon.stub sshHelper, 'writeKeyFile', (callback) ->
          callback(null, ['sshArg1', 'sshArg2'], deleteKeyFileSpy)
        sinon.stub childProcess, 'execFile', (file, args, opts, cb) ->
          cb(err, 'fake stdout', 'fake stderr')
        sshHelper.execCommand('ls', cbSpy)
        sshHelper.writeKeyFile.called.should.be.true

      afterEach ->
        childProcess.execFile.restore()

      it 'executes a given command', ->
        childProcess.execFile.called.should.be.true
        childProcess.execFile.args[0][0].should.equal '/usr/bin/ssh'
        childProcess.execFile.args[0][1].should.eql ['sshArg1', 'sshArg2', 'LC_ALL=en_US.UTF-8', 'ls']
        childProcess.execFile.args[0][2].should.eql { timeout: 20000 }

      it 'calls deleteKeyFile function', ->
        deleteKeyFileSpy.called.should.be.true

      it 'makes a callback with given err, stdout, and stderr', ->
        cbSpy.calledWith(err, 'fake stdout', 'fake stderr').should.be.true

