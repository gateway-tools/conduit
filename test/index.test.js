const configuration = require("../configuration/config")
const server = require("../server/server")
const axios = require('axios').default;


switch (process.env.NODE_ENV) {
  case "test":
    before(function (done) {
      server.start()
      done();
    });
    
    describe("Return static content from ENS lookup", function () {
      it("should successfully respond with a 200 upon startup", async function () {
        let testRequest = await axios({
          method: "get",
          "url": "http://localhost:" + configuration.router.listen,
          "headers": { "Host": configuration.tests.hostname }
        })
      })
    })
    
    switch (configuration.ask.enabled) {
      case "true":
        describe("Return contenthash record from /ask endpoint", function () {
          it("should successfully return a record's contenthash", async function () {
            let testRequest = await axios({
              method: "get",
              "url": "http://localhost:" + configuration.ask.listen + "/ask?domain=" + configuration.tests.hostname
            })
          })
        })   
    }
    
    after(function (done) {
      process.exit()
    });
    break;
  default:
    break;
}