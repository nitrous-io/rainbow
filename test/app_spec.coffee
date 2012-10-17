MessageVerifier = require('action-base').MessageVerifier
app = require '../app'

describe 'app', ->
  it 'has a message verifier', ->
    expect(app.messageVerifier).to.be.an.instanceOf MessageVerifier
    expect(app.messageVerifier.secret).to.equal app.settings.secretToken

