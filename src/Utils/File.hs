-- From elm-make/src/Utils/File.hs
module Utils.File where

import           Control.Monad.Except (liftIO)
import qualified Data.Binary          as Binary
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text            as Text
import qualified Data.Text.IO         as TextIO
import           GHC.IO.Exception     (IOErrorType (InvalidArgument))
import           System.Directory     (createDirectoryIfMissing, doesFileExist)
import           System.FilePath      (dropFileName)
import           System.IO            (Handle, IOMode (ReadMode, WriteMode),
                                       hSetEncoding, utf8, withBinaryFile,
                                       withFile)
import           System.IO.Error      (annotateIOError, ioeGetErrorType,
                                       modifyIOError)

-- import qualified BuildManager as BM
writeBinary :: (Binary.Binary a) => FilePath -> a -> IO ()
writeBinary path value =
  do
    let dir = dropFileName path
    createDirectoryIfMissing True dir
    withBinaryFile path WriteMode $ \handle -> LBS.hPut handle (Binary.encode value)

readBinary :: (Binary.Binary a) => FilePath -> IO a
readBinary path =
  do
    exists <- liftIO (doesFileExist path)
    if exists
      then decode
      else ioError (userError path)

  where
    decode =
      do
        bits <- liftIO (LBS.readFile path)
        case Binary.decodeOrFail bits of
          Left _ ->
            ioError (userError path)

          Right (_, _, value) ->
            return value

{-|
  readStringUtf8 converts Text to String instead of reading
  a String directly because System.IO.hGetContents is lazy,
  and with lazy IO, decoding exception cannot be caught.
  By using the strict Text type, we force any decoding
  exceptions to be thrown so we can show our UTF-8 message.
-}
readStringUtf8 :: FilePath -> IO String
readStringUtf8 name =
  readTextUtf8 name >>= (return . Text.unpack)

readTextUtf8 :: FilePath -> IO Text.Text
readTextUtf8 name =
  let action handle =
                       modifyIOError (convertUtf8Error name) (TextIO.hGetContents handle)
  in withFileUtf8 name ReadMode action

convertUtf8Error :: FilePath -> IOError -> IOError
convertUtf8Error filepath e =
  case ioeGetErrorType e of
    InvalidArgument -> utf8Error
    _               -> e
  where
    errorMessage = "Bad encoding; the file must be valid UTF-8"
    utf8Error = annotateIOError (userError errorMessage) "" Nothing (Just filepath)

writeStringUtf8 :: FilePath -> String -> IO ()
writeStringUtf8 f str =
  writeTextUtf8 f (Text.pack str)

writeTextUtf8 :: FilePath -> Text.Text -> IO ()
writeTextUtf8 f txt =
  withFileUtf8 f WriteMode (\handle -> TextIO.hPutStr handle txt)

withFileUtf8 :: FilePath -> IOMode -> (Handle -> IO a) -> IO a
withFileUtf8 f mode action =
  withFile f mode (\handle -> hSetEncoding handle utf8 >> action handle)
