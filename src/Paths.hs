
-- This is a replacment for cabal's autogenerated Paths_nikki.hs
-- Use this instead to find data files.
-- Needed for deployment in one folder (e.g. on windows)

module Paths (getDataFileName, getDataFiles) where


import Data.List

import Control.Arrow

import System.Info
import System.FilePath
import System.Directory
import System.Environment.FindBin

import qualified Paths_nikki


getDataFileName :: FilePath -> IO FilePath
getDataFileName p = do
  progPath <- getProgPath
  putStrLn ("DEBUG: path to executable: " ++ progPath)
  case os of
    "linux" -> Paths_nikki.getDataFileName p -- standard cabal behaviour
    "mingw32" ->
        -- works if the application is deployed in one folder
        return (progPath </> "data" </> p)
    "darwin" ->
        -- works if the application is bundled in an app
        return (progPath </> ".." </> "Resources" </> "resources" </> p)
    x -> error ("unsupported os: " ++ os)

-- | returns unhidden files with a given extension in a given data directory.
getDataFiles :: String -> FilePath -> IO [FilePath]
getDataFiles extension path_ = do
    path <- getDataFileName path_
    files <- getDirectoryContents path
    return $
        map (path </>) $
        sort $
        filter (\ f -> not ("." `isPrefixOf` f)) $
        filter (\ f -> takeExtension f == extension) $
        files
