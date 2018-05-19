module Main (main) where

import System.FilePath.Glob (glob)
import Test.DocTest (doctest)

import Data.Char (toLower)
import Data.List (isSuffixOf)

import System.Exit (exitSuccess)

import Utils.SBVTestFramework (getTestEnvironment, TestEnvironment(..), CIOS(..))

main :: IO ()
main = do (testEnv, testPercentage) <- getTestEnvironment

          putStrLn $ "SBVDocTest: Test platform: " ++ show testEnv

          case testEnv of
            TestEnvLocal   -> runDocTest False
            TestEnvCI env  -> if testPercentage < 50
                              then do putStrLn $ "Test percentage below tresheold, skipping doctest: " ++ show testPercentage
                                      exitSuccess
                              else runDocTest (env == CIWindows)
            TestEnvUnknown  -> do putStrLn "Unknown test environment, skipping doctests"
                                  exitSuccess

 where runDocTest windowsSkip = do srcFiles <- glob "Data/SBV/**/*.hs"
                                   docFiles <- glob "Documentation/SBV/**/*.hs"

                                   let allFiles = srcFiles ++ docFiles
                                       testFiles
                                         | windowsSkip = filter (not . bad) allFiles
                                         | True        = allFiles
                                       args = ["--fast", "--no-magic"]

                                   doctest $ args ++ testFiles

       -- The following test has a path encoded in its output, and hence fails on Windows
       -- since it has the c:\blah\blah format. Skip it:
       bad fn = "nodiv0.hs" `isSuffixOf` map toLower fn

