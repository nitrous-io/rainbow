MessageVerifier = require '../app/lib/message_verifier'

describe 'app', ->
  it 'has a message verifier', ->
    expect(app.messageVerifier).to.be.an.instanceOf MessageVerifier
    expect(app.messageVerifier.secret).to.equal app.settings.secretToken

