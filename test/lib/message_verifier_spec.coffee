MessageVerifier = require '../../app/lib/message_verifier'

describe 'MessageVerifier', ->
  [verifier, message] = []

  beforeEach ->
    verifier = new MessageVerifier('foobar')
    message = 'WyJmb28iLCJiYXIiXQ==--0898cb188ac378e6ba570f7fe2a946d2a51a4b13' # '["foo","bar"]' in base64

  describe '#verify', ->
    context 'valid signed message', ->
      it 'returns the original object', ->
        verifier.verify(message).should.eql ['foo', 'bar']

    context 'invalid signed message', ->
      beforeEach ->
        message = 'WyJmb28iLCJiYXIiXQ==--236i789834569723950781239048710293471024'

      it 'returns null', ->
        expect(verifier.verify(message)).to.be null

    context 'empty message', ->
      it 'returns null', ->
        expect(verifier.verify('')).to.be null

    context 'null message', ->
      it 'returns null', ->
        expect(verifier.verify(null)).to.be null

  describe '#generate', ->
    it 'generates signed message', ->
      verifier.generate(['foo', 'bar']).should.eql message

