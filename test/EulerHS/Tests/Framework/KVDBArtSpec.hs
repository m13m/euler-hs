module EulerHS.Tests.Framework.KVDBArtSpec
  ( spec
  ) where

import           EulerHS.Prelude

import           Data.Aeson as A
import           Test.Hspec

import qualified Database.Redis as R
import           EulerHS.Language as L
import           EulerHS.Runtime
import           EulerHS.Tests.Framework.Common
import           EulerHS.Types as T

connectInfo :: R.ConnectInfo
connectInfo = R.defaultConnectInfo {R.connectHost = "redis"}

runWithRedisConn_ :: ResultRecording -> Flow b -> IO b
runWithRedisConn_ = replayRecording

spec :: Spec
spec = do
  describe "ART KVDB tests" $ do
    it "get a correct key" $ do
      result <- runWithRedisConn_ getKey $ L.runKVDB "redis" $ do
        L.set "aaa" "bbb"
        res <- L.get "aaa"
        L.del ["aaa"]
        pure res
      result `shouldBe` Right (Just "bbb")

    it "get a wrong key" $ do
      result <- runWithRedisConn_ getWrongKey $ L.runKVDB "redis" $ do
        L.set "aaa" "bbb"
        res <- L.get "aaac"
        L.del ["aaa"]
        pure res
      result `shouldBe` Right Nothing

    it "delete existing keys" $ do
      result <- runWithRedisConn_ deleteExisting $ L.runKVDB "redis" $ do
        L.set "aaa" "bbb"
        L.set "ccc" "ddd"
        L.del ["aaa", "ccc"]
      result `shouldBe` Right 2

    it "delete keys (w/ no keys)" $ do
      result <- runWithRedisConn_ deleteKeysNoKeys $ L.runKVDB "redis" $ do
        L.del []
      result `shouldBe` Right 0

    it "delete missing keys" $ do
      result <- runWithRedisConn_ deleteMissing $ L.runKVDB "redis" $ do
        L.del ["zzz", "yyy"]
      result `shouldBe` Right 0

    it "get a correct key from transaction" $ do
      result <- runWithRedisConn_ getCorrectFromTx $ L.runKVDB "redis" $ L.multiExec $ do
        L.setTx "aaa" "bbb"
        res <- L.getTx "aaa"
        L.delTx ["aaa"]
        pure res
      result `shouldBe` Right (T.TxSuccess (Just "bbb"))

    it "get incorrect key from transaction" $ do
      result <- runWithRedisConn_ getIncorrectFromTx $ L.runKVDB "redis" $ L.multiExec $ do
        res <- L.getTx "aaababababa"
        pure res
      result `shouldBe` Right (T.TxSuccess Nothing)

    it "setex sets value" $ do
      let hour = 60 * 60
      result <- runWithRedisConn_ setExGetKey $ L.runKVDB "redis" $ do
        L.setex "aaaex" hour "bbbex"
        res <- L.get "aaaex"
        L.del ["aaaex"]
        pure res
      result `shouldBe` Right (Just "bbbex")

    it "setex ttl works" $ do
      result <- runWithRedisConn_ setExTtl $ do
        L.runKVDB "redis" $ L.setex "aaaex" 1 "bbbex"
        L.runIO $ threadDelay (2 * 10 ^ 6)
        L.runKVDB "redis" $ do
          res <- L.get "aaaex"
          L.del ["aaaex"]
          pure res
      result `shouldBe` Right Nothing

    it "set only if not exist" $ do
      result <- runWithRedisConn_ setIfNotExist $ L.runKVDB "redis" $ do
        res1 <- L.setOpts "aaa" "bbb" L.NoTTL L.SetIfNotExist
        res2 <- L.get "aaa"
        res3 <- L.setOpts "aaa" "ccc" L.NoTTL L.SetIfNotExist
        res4 <- L.get "aaa"
        L.del ["aaa"]
        pure (res1, res2, res3, res4)
      result `shouldBe` Right (True, Just "bbb", False, Just "bbb")

    it "set only if exist" $ do
      result <- runWithRedisConn_ setIfExist $ L.runKVDB "redis" $ do
        res1 <- L.setOpts "aaa" "bbb" L.NoTTL L.SetIfExist
        res2 <- L.get "aaa"
        L.set "aaa" "bbb"
        res3 <- L.setOpts "aaa" "ccc" L.NoTTL L.SetIfExist
        res4 <- L.get "aaa"
        L.del ["aaa"]
        pure (res1, res2, res3, res4)
      result `shouldBe` Right (False, Nothing, True, Just "ccc")

    it "set px ttl works" $ do
      result <- runWithRedisConn_ setPxTtl $ do
        L.runKVDB "redis" $ L.setOpts "aaapx" "bbbpx" (L.Milliseconds 500) L.SetAlways
        res1 <- L.runKVDB "redis" $ L.get "aaapx"
        L.runIO $ threadDelay (10 ^ 6)
        res2 <- L.runKVDB "redis" $ L.get "aaapx"
        L.runKVDB "redis" $ L.del ["aaapx"]
        pure (res1, res2)
      result `shouldBe` (Right (Just "bbbpx"), Right Nothing)

    it "xadd create and update stream" $ do
      result <- runWithRedisConn_ xaddXlen $ L.runKVDB "redis" $ do
        L.xadd "aaas" L.AutoID [("a", "1"), ("b", "2")]
        res1 <- L.xlen "aaas"
        L.xadd "aaas" L.AutoID [("c", "3")]
        res2 <- L.xlen "aaas"
        L.del ["aaas"]
        res3 <- L.xlen "aaas"
        pure (res1, res2, res3)
      result `shouldBe` Right (1, 2, 0)


getKey :: ResultRecording
getKey = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonValue\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonResult\":{\"Right\":1},\"jsonKeys\":[{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

getWrongKey :: ResultRecording
getWrongKey = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonValue\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":{\"Right\":null},\"jsonKey\":{\"utf8\":\"aaac\",\"b64\":\"YWFhYw==\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonResult\":{\"Right\":1},\"jsonKeys\":[{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

deleteExisting :: ResultRecording
deleteExisting = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonValue\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"SetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonValue\":{\"utf8\":\"ddd\",\"b64\":\"ZGRk\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"ccc\",\"b64\":\"Y2Nj\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonResult\":{\"Right\":2},\"jsonKeys\":[{\"utf8\":\"aaa\",\"b64\":\"YWFh\"},{\"utf8\":\"ccc\",\"b64\":\"Y2Nj\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

deleteKeysNoKeys :: ResultRecording
deleteKeysNoKeys = fromJust $ decode "{\"recording\":[{\"_entryName\":\"DelEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonResult\":{\"Right\":0},\"jsonKeys\":[]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

deleteMissing :: ResultRecording
deleteMissing = fromJust $ decode "{\"recording\":[{\"_entryName\":\"DelEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonResult\":{\"Right\":0},\"jsonKeys\":[{\"utf8\":\"zzz\",\"b64\":\"enp6\"},{\"utf8\":\"yyy\",\"b64\":\"eXl5\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

getCorrectFromTx :: ResultRecording
getCorrectFromTx = fromJust $ decode "{\"recording\":[{\"_entryName\":\"MultiExecEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"tag\":\"TxSuccess\",\"contents\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"}}}},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

getIncorrectFromTx :: ResultRecording
getIncorrectFromTx = fromJust $ decode "{\"recording\":[{\"_entryName\":\"MultiExecEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"tag\":\"TxSuccess\",\"contents\":null}}},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

setExGetKey :: ResultRecording
setExGetKey = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetExEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonTtl\":3600,\"jsonValue\":{\"utf8\":\"bbbex\",\"b64\":\"YmJiZXg=\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"aaaex\",\"b64\":\"YWFhZXg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"utf8\":\"bbbex\",\"b64\":\"YmJiZXg=\"}},\"jsonKey\":{\"utf8\":\"aaaex\",\"b64\":\"YWFhZXg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonResult\":{\"Right\":1},\"jsonKeys\":[{\"utf8\":\"aaaex\",\"b64\":\"YWFhZXg=\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

setExTtl :: ResultRecording
setExTtl = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetExEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonTtl\":1,\"jsonValue\":{\"utf8\":\"bbbex\",\"b64\":\"YmJiZXg=\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"aaaex\",\"b64\":\"YWFhZXg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"RunIOEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":[],\"description\":\"\"},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonResult\":{\"Right\":null},\"jsonKey\":{\"utf8\":\"aaaex\",\"b64\":\"YWFhZXg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":3,\"_entryPayload\":{\"jsonResult\":{\"Right\":0},\"jsonKeys\":[{\"utf8\":\"aaaex\",\"b64\":\"YWFhZXg=\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

setIfNotExist :: ResultRecording
setIfNotExist = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetOptsEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonTTL\":{\"tag\":\"NoTTL\"},\"jsonValue\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"},\"jsonCond\":\"SetIfNotExist\",\"jsonResult\":{\"Right\":true},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"SetOptsEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonTTL\":{\"tag\":\"NoTTL\"},\"jsonValue\":{\"utf8\":\"ccc\",\"b64\":\"Y2Nj\"},\"jsonCond\":\"SetIfNotExist\",\"jsonResult\":{\"Right\":false},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":3,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":4,\"_entryPayload\":{\"jsonResult\":{\"Right\":1},\"jsonKeys\":[{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

setIfExist :: ResultRecording
setIfExist = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetOptsEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonTTL\":{\"tag\":\"NoTTL\"},\"jsonValue\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"},\"jsonCond\":\"SetIfExist\",\"jsonResult\":{\"Right\":false},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":{\"Right\":null},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"SetEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonValue\":{\"utf8\":\"bbb\",\"b64\":\"YmJi\"},\"jsonResult\":{\"Right\":{\"tag\":\"Ok\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"SetOptsEntry\",\"_entryIndex\":3,\"_entryPayload\":{\"jsonTTL\":{\"tag\":\"NoTTL\"},\"jsonValue\":{\"utf8\":\"ccc\",\"b64\":\"Y2Nj\"},\"jsonCond\":\"SetIfExist\",\"jsonResult\":{\"Right\":true},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":4,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"utf8\":\"ccc\",\"b64\":\"Y2Nj\"}},\"jsonKey\":{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":5,\"_entryPayload\":{\"jsonResult\":{\"Right\":1},\"jsonKeys\":[{\"utf8\":\"aaa\",\"b64\":\"YWFh\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

setPxTtl :: ResultRecording
setPxTtl = fromJust $ decode "{\"recording\":[{\"_entryName\":\"SetOptsEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonTTL\":{\"tag\":\"Milliseconds\",\"contents\":500},\"jsonValue\":{\"utf8\":\"bbbpx\",\"b64\":\"YmJicHg=\"},\"jsonCond\":\"SetAlways\",\"jsonResult\":{\"Right\":true},\"jsonKey\":{\"utf8\":\"aaapx\",\"b64\":\"YWFhcHg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonResult\":{\"Right\":{\"utf8\":\"bbbpx\",\"b64\":\"YmJicHg=\"}},\"jsonKey\":{\"utf8\":\"aaapx\",\"b64\":\"YWFhcHg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"RunIOEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonResult\":[],\"description\":\"\"},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"GetEntry\",\"_entryIndex\":3,\"_entryPayload\":{\"jsonResult\":{\"Right\":null},\"jsonKey\":{\"utf8\":\"aaapx\",\"b64\":\"YWFhcHg=\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":4,\"_entryPayload\":{\"jsonResult\":{\"Right\":0},\"jsonKeys\":[{\"utf8\":\"aaapx\",\"b64\":\"YWFhcHg=\"}]},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"

xaddXlen :: ResultRecording
xaddXlen = fromJust $ decode "{\"recording\":[{\"_entryName\":\"XAddEntry\",\"_entryIndex\":0,\"_entryPayload\":{\"jsonStream\":{\"utf8\":\"aaas\",\"b64\":\"YWFhcw==\"},\"jsonItems\":[[{\"utf8\":\"a\",\"b64\":\"YQ==\"},{\"utf8\":\"1\",\"b64\":\"MQ==\"}],[{\"utf8\":\"b\",\"b64\":\"Yg==\"},{\"utf8\":\"2\",\"b64\":\"Mg==\"}]],\"jsonResult\":{\"Right\":[1596654345484,0]},\"jsonEntryId\":{\"tag\":\"AutoID\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"XLenEntry\",\"_entryIndex\":1,\"_entryPayload\":{\"jsonStream\":{\"utf8\":\"aaas\",\"b64\":\"YWFhcw==\"},\"jsonResult\":{\"Right\":1}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"XAddEntry\",\"_entryIndex\":2,\"_entryPayload\":{\"jsonStream\":{\"utf8\":\"aaas\",\"b64\":\"YWFhcw==\"},\"jsonItems\":[[{\"utf8\":\"c\",\"b64\":\"Yw==\"},{\"utf8\":\"3\",\"b64\":\"Mw==\"}]],\"jsonResult\":{\"Right\":[1596654345485,0]},\"jsonEntryId\":{\"tag\":\"AutoID\"}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"XLenEntry\",\"_entryIndex\":3,\"_entryPayload\":{\"jsonStream\":{\"utf8\":\"aaas\",\"b64\":\"YWFhcw==\"},\"jsonResult\":{\"Right\":2}},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"DelEntry\",\"_entryIndex\":4,\"_entryPayload\":{\"jsonResult\":{\"Right\":1},\"jsonKeys\":[{\"utf8\":\"aaas\",\"b64\":\"YWFhcw==\"}]},\"_entryReplayMode\":\"Normal\"},{\"_entryName\":\"XLenEntry\",\"_entryIndex\":5,\"_entryPayload\":{\"jsonStream\":{\"utf8\":\"aaas\",\"b64\":\"YWFhcw==\"},\"jsonResult\":{\"Right\":0}},\"_entryReplayMode\":\"Normal\"}],\"forkedRecordings\":{},\"safeRecordings\":{}}"
