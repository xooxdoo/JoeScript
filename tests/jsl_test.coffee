require './setup'

{clazz, colors:{red, blue, cyan, magenta, green, normal, black, white, yellow}} = require('cardamom')
{inspect} = require 'util'
{equal, deepEqual, ok} = require 'assert'
{
  JThread, JKernel, GOD,
  NODES:{JObject, JArray, JUser, JUndefined, JNull, JNaN, JBoundFunc, JStub}
  GLOBALS:GLOBALS
  HELPERS:{isInteger,isObject,setLast}
} = require 'joeson/src/interpreter'

JSL = require 'joeson/src/parsers/jsl'

console.log blue "\n-= JSL test =-"

tests = []
test = (code, str, callback) -> tests.push {code,str,callback}
canon = (str) -> str.replace(/#[a-zA-Z0-9]{1,64}/g, '#').replace(/@[a-zA-Z0-9]{1,64}/g, '@')

test " ''+[1,2,3] ",                      '{A|#@ 0:1,1:2,2:3}',           -> deepEqual @it.jsValue(@thread), [1,2,3]
test " ''+[] ",                           '{A|#@ }',                      -> deepEqual @it.jsValue(@thread), []
test " ''+{foo:'bar'} ",                  '{O|#@ "foo":"bar"}',           -> deepEqual @it.jsValue(@thread), {foo:'bar'}
test """
foo = {}
foo.bar = 1
foo.baz = ->
''+foo
""",                                      '{O|#@ \"bar\":1,\"baz\":<#>}', -> js=@it.jsValue(@thread); equal js.bar, 1
test """
foo = {}
foo.bar = 1
foo.foo = foo
''+foo
""",                                      '{O|#@ \"bar\":1,\"foo\":<#>}', -> js=@it.jsValue(@thread); equal js.bar, 1; equal js.foo, js

counter = 0
runNextTest = ->
  return if tests.length is 0
  {code, str, callback} = tests.shift()
  console.log "#{red "test #{counter++}:"}\n#{normal code}"
  kernel = new JKernel()
  try
    kernel.run
      code:code
      stdin:undefined
      stdout: (msg) -> process.stdout.write(msg)
      stderr: (msg) -> process.stderr.write(msg)
      callback: ->
        try
          if @error?
            console.log red "Error in running code:"
            @printErrorStack()
            process.exit(1)
            return
          # first, see if str matches.
          resStr = @last.jsValue()
          equal canon(resStr), str, "Expected serialized '#{str}' but got '#{canon(resStr)}'"
          # now parse it back
          try
            resObj = JSL.parse @, resStr
          catch err
            console.log red "Error in parsing resStr '#{resStr}':"
            console.log red err.stack ? err
            try
              resObj = JSL.parse @, resStr, debug:yes
            process.exit(1)
          # now try the callback if exists.
          callback?.call context:@, it:resObj, thread:@
          # callbacks are synchronous.
          # if it didn't throw, it was successful.
          runNextTest()
        catch err
          console.log red "Unknown Error:"
          console.log red err.stack ? err
          process.exit(1)
  catch err
    console.log red "KERNEL ERROR:"
    console.log red err.stack ? err
    process.exit(1)
runNextTest()