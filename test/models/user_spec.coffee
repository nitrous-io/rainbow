User = require '../../app/models/user'
BaseModel = require('action-base').BaseModel
MessageVerifier = require('action-base').MessageVerifier
settings = require '../../config/settings'

describe 'User', ->
  it 'is a subclass of BaseModel', ->
    expect(new User).to.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    expect(User.tableName).to.equal 'users'

  describe '#passwordSalt', ->
    user = null

    beforeEach ->
      user = new User

    context 'when encrypted_password is absent', ->
      beforeEach ->
        user.encrypted_password = null

      it 'returns null', ->
        expect(user.passwordSalt()).to.be.null

    context 'when encrypted_password is present', ->
      beforeEach ->
        user.encrypted_password = '$2a$10$Z/uz106hoAT7lRhA1mLYS.l9x2VCB5tmzTEBZzSWYuqzhsdpriApe'

      it 'returns salt component of encrypted_password', ->
        expect(user.passwordSalt()).to.equal '$2a$10$Z/uz106hoAT7lRhA1mLYS.'

  describe '.verifyUserSession', ->
    before ->
      settings.secretToken = 'secret_token'

    context 'when the session is invalid', ->
      it 'makes callback with null', (done) ->
        User.verifyUserSession 'invalid session !@#$%^', (err, user) ->
          expect(err).to.be.null
          expect(user).to.be.null
          done()

    context 'when the session is valid', ->
      session = null

      context 'when the session does not contain warden.user.user.key object', ->
        beforeEach ->
          session = new MessageVerifier('secret_token').generate foo: 'bar'

        it 'makes callback with null', (done) ->
          User.verifyUserSession session, (err, user) ->
            expect(err).to.be.null
            expect(user).to.be.null
            done()

      context 'when the session contains warden.user.user.key object, but one that does not contain user id', ->
        beforeEach ->
          session = new MessageVerifier('secret_token').generate 'warden.user.user.key': ['User', null, '$2a$10$Z/uz106hoAT7lRhA1mLYS.']

        it 'makes callback with null', (done) ->
          User.verifyUserSession session, (err, user) ->
            expect(err).to.be.null
            expect(user).to.be.null
            done()

      context 'when the session contains warden.user.user.key object, but one that does not contain password salt', ->
        beforeEach ->
          session = new MessageVerifier('secret_token').generate 'warden.user.user.key': ['User', [123], null]

        it 'makes callback with null', (done) ->
          User.verifyUserSession session, (err, user) ->
            expect(err).to.be.null
            expect(user).to.be.null
            done()

      context 'when the session contains warden.user.user.key object with the user id and salt', ->
        beforeEach ->
          session = new MessageVerifier('secret_token').generate 'warden.user.user.key': ['User', [123], '$2a$10$Z/uz106hoAT7lRhA1mLYS.']

        context 'when the user lookup fails with error', ->
          error = null

          beforeEach ->
            error = new Error
            sinon.stub User, 'findById', (id, columns, callback) ->
              callback = columns if typeof columns == 'function'
              callback error, null

          afterEach ->
            User.findById.restore()

          it 'makes callback with null', (done) ->
            User.verifyUserSession session, (err, user) ->
              expect(err).to.equal error
              expect(user).to.be.null
              done()

        context 'when the user with a id given in the session is absent', ->
          beforeEach ->
            sinon.stub User, 'findById', (id, columns, callback) ->
              callback = columns if typeof columns == 'function'
              callback null, null

          afterEach ->
            User.findById.restore()

          it 'makes callback with null', (done) ->
            User.verifyUserSession session, (err, user) ->
              expect(err).to.be.null
              expect(user).to.be.null
              done()

        context 'when the user with a id given in the session exists', ->
          user = null

          beforeEach ->
            user = new User
            user.id = 123

            sinon.stub User, 'findById', (id, columns, callback) ->
              callback = columns if typeof columns == 'function'
              callback null, user

          afterEach ->
            User.findById.restore()

          context 'when the password salt given in the session is incorrect', ->
            beforeEach ->
              user.encrypted_password = '123wr0ngP@ssw0rdS@lt123456789Password'

            it 'makes callback with null', (done) ->
              User.verifyUserSession session, (err, user) ->
                expect(err).to.be.null
                expect(user).to.be.null
                done()

          context 'when the password salt given in the session is correct', ->
            beforeEach ->
              user.encrypted_password = '$2a$10$Z/uz106hoAT7lRhA1mLYS.l9x2VCB5tmzTEBZzSWYuqzhsdpriApe'

            it 'finds a user with the user id in the session and then verifies the password salt', (done) ->
              User.verifyUserSession session, (err, user) ->
                expect(err).to.be.null
                expect(user).to.equal.user
                done()

