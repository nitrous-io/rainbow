AuthTokenVerifier = require '../../app/lib/auth_token_verifier'
MessageVerifier = require('action-base').MessageVerifier
app = require '../../app'

describe 'AuthTokenVerifier', ->
  authTokenVerifier = messageVerifier = null

  beforeEach ->
    messageVerifier = app.messageVerifier
    authTokenVerifier = new AuthTokenVerifier 'rainbow', messageVerifier

  describe 'constructor', ->
    it 'sets @name and @messageVerifier', ->
      expect(authTokenVerifier.name).to.equal 'rainbow'
      expect(authTokenVerifier.messageVerifier).to.equal messageVerifier

  describe '#verify', ->
    token = clock = null

    beforeEach ->
      clock = sinon.useFakeTimers(+new Date)

    afterEach ->
      clock.restore()

    encodeToken = (messageVerifier, obj) ->
      new Buffer(messageVerifier.generate(obj), 'utf8').toString 'base64'

    context 'when token is valid', ->
      context 'when token has a matching name', ->
        context 'when token is expired', ->
          beforeEach ->
            expiresAt = Math.floor(+new Date / 1000)
            token = encodeToken(messageVerifier, [123, "rainbow", expiresAt])

          it 'returns null', ->
            expect(authTokenVerifier.verify token).to.be.null

        context 'when token is not yet expired', ->
          beforeEach ->
            expiresAt = Math.floor(+new Date / 1000) + 1
            token = encodeToken(messageVerifier, [123, "rainbow", expiresAt])

          it 'returns userId', ->
            expect(authTokenVerifier.verify token).to.equal 123

      context 'when token does not have a matching name', ->
        beforeEach ->
          expiresAt = Math.floor(+new Date / 1000) + 1
          token = encodeToken(messageVerifier, [123, "unicorn", expiresAt])

        it 'returns null', ->
          expect(authTokenVerifier.verify token).to.be.null

    context 'when token is invalid', ->
      beforeEach ->
        messageVerifier = new MessageVerifier 'invalidToken'
        expiresAt = Math.floor(+new Date / 1000) + 1
        token = encodeToken(messageVerifier, [123, "unicorn", expiresAt])

      it 'returns null', ->
        expect(authTokenVerifier.verify token).to.be.null

