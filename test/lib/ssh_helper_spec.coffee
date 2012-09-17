SSHHelper = require '../../app/lib/ssh_helper'
fs = require 'fs'
tmp = require 'tmp'
childProcess = require 'child_process'

describe 'SSHHelper', ->
  sshHelper = null

  beforeEach ->
    sshHelper = new SSHHelper 'peter', 'localhost', '2222', 'ssh-rsa AAAB3NzaC1yc2EAAA peter@kim'

  describe '#writeKeyFile', ->
    err = cbSpy = null

    context 'when temp file failed to get created', ->
      beforeEach ->
        err = new Error
        sinon.stub tmp, 'file', (cb) ->
          cb(err)
        cbSpy = sinon.spy()
        sshHelper.writeKeyFile cbSpy

      afterEach ->
        tmp.file.restore()

      it 'makes a callback with the error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when temp file is successfully created', ->
      fakeFd = null

      beforeEach ->
        err = new Error
        fakeFd = {}
        sinon.stub tmp, 'file', (cb) ->
          cb null, '/tmp/tmpfile', fakeFd
        sinon.stub fs, 'unlink', (path, cb) ->
          cb()

      afterEach ->
        tmp.file.restore()
        fs.unlink.restore()

      context 'when the key failed to be written to the temp file', ->
        beforeEach ->
          fs.write = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            expect(fd).to.equal fakeFd
            cb err
          cbSpy = sinon.spy()
          sshHelper.writeKeyFile cbSpy
          expect(fs.write).to.have.been.called

        afterEach ->
          fs.write.restore()

        it 'deletes the temp file', ->
          expect(fs.unlink).to.have.been.called
          expect(fs.unlink.args[0][0]).to.equal '/tmp/tmpfile'

        it 'makes a callback with the error', ->
          expect(cbSpy).to.have.been.calledWith err

      context 'when the key is successfully written to the temp file', ->
        beforeEach ->
          fs.write = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            expect(fd).to.equal fakeFd
            cb()
          cbSpy = sinon.spy()
          sshHelper.writeKeyFile cbSpy
          expect(fs.write).to.have.been.called

        afterEach ->
          fs.write.restore()

        it 'makes a callback with ssh arguments as the first argument', ->
          expect(cbSpy).to.have.been.called
          sshArgs = cbSpy.args[0][1].join ' '
          expect(sshArgs).to.match /^-i \/tmp\/tmpfile/
          expect(sshArgs).to.match /-o UserKnownHostsFile=\/dev\/null/
          expect(sshArgs).to.match /-o StrictHostKeyChecking=no/
          expect(sshArgs).to.match /-o PubkeyAuthentication=yes/
          expect(sshArgs).to.match /-o PasswordAuthentication=no/
          expect(sshArgs).to.match /-o LogLevel=FATAL/
          expect(sshArgs).to.match /-p 2222/
          expect(sshArgs).to.match /peter@localhost/

        describe 'deleteKeyFile function', ->
          context 'with a callback', ->
            it 'deletes the temp key file and then calls the callback', (done) ->
              expect(cbSpy).to.have.been.called
              cbSpy.args[0][2] ->
                expect(fs.unlink).to.have.been.called
                expect(fs.unlink.args[0][0]).to.equal '/tmp/tmpfile'
                done()

          context 'without a callback', ->
            it 'deletes the temp key file', ->
              expect(cbSpy).to.have.been.called
              cbSpy.args[0][2]()
              expect(fs.unlink).to.have.been.called
              expect(fs.unlink.args[0][0]).to.equal '/tmp/tmpfile'

  describe '#execCommand', ->
    err = cbSpy = null

    context 'when writeKeyFile fails with error', ->
      beforeEach ->
        err = new Error
        cbSpy = sinon.spy()
        sinon.stub sshHelper, 'writeKeyFile', (callback) ->
          callback(err)
        sshHelper.execCommand 'ls', cbSpy
        expect(sshHelper.writeKeyFile).to.have.been.called

      it 'makes a callback with the error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when writeKeyFile succeeds', ->
      deleteKeyFileSpy = null

      beforeEach ->
        deleteKeyFileSpy = sinon.spy (cb) -> cb()
        cbSpy = sinon.spy()
        sinon.stub sshHelper, 'writeKeyFile', (callback) ->
          callback null, ['sshArg1', 'sshArg2'], deleteKeyFileSpy
        sinon.stub childProcess, 'execFile', (file, args, opts, cb) ->
          cb err, 'fake stdout', 'fake stderr'
        sshHelper.execCommand 'ls', cbSpy
        expect(sshHelper.writeKeyFile).to.have.been.called

      afterEach ->
        childProcess.execFile.restore()

      it 'executes a given command', ->
        expect(childProcess.execFile).to.have.been.called
        expect(childProcess.execFile.args[0][0]).to.equal '/usr/bin/ssh'
        expect(childProcess.execFile.args[0][1]).to.deep.equal ['sshArg1', 'sshArg2', 'export LC_ALL=en_US.UTF-8; ls']
        expect(childProcess.execFile.args[0][2]).to.deep.equal { timeout: 20000 }

      it 'calls deleteKeyFile function', ->
        expect(deleteKeyFileSpy).to.have.been.called

      it 'makes a callback with given err, stdout, and stderr', ->
        expect(cbSpy).to.have.been.calledWith err, 'fake stdout', 'fake stderr'

