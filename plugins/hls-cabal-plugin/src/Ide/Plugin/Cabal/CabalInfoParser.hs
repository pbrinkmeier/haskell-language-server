{-# LANGUAGE OverloadedStrings #-}

-- | This module allows you to parse the output of @cabal info@.
module Ide.Plugin.Cabal.CabalInfoParser (parseCabalInfo, cabalInfo) where

import           Data.Map.Strict   (Map)
import           Data.Text         (Text)
import           Data.Void         (Void)
import           Text.Megaparsec   (MonadParsec (..), Parsec, chunk, many,
                                    parse, sepBy, single, (<|>))

import           Control.Monad     (void)
import           Data.Either.Extra (mapLeft)
import qualified Data.Map.Strict   as Map
import qualified Data.Text         as T

type Parser = Parsec Void Text

parseCabalInfo :: Text -> Either CabalInfoParserError (Map Text (Map Text [Text]))
parseCabalInfo = mapLeft (T.pack . show) . parse cabalInfo ""

type CabalInfoParserError = Text

-- TODO: parse eof at the end to avoid early exits
cabalInfo :: Parser (Map Text (Map Text [Text]))
cabalInfo = do
    entries <- cabalInfoEntry `sepBy` chunk "\n\n"
    void $ takeWhileP (Just "trailing whitespace") (`elem` (" \t\r\n" :: String))
    eof

    pure $ Map.fromList entries

cabalInfoEntry :: Parser (Text, Map Text [Text])
cabalInfoEntry = do
    void $ single '*'
    void spaces

    name <- takeWhileP (Just "package name") (/= ' ')

    void restOfLine

    pairs <- many $ try kvPair

    pure (name, Map.fromList pairs)

kvPair :: Parser (Text, [Text])
kvPair = do
    spacesBeforeKey <- spaces
    key <- takeWhileP (Just "field name") (/= ':')
    void $ single ':'
    spacesAfterKey <- spaces
    firstLine <- restOfLine

    -- The first line of the field may be empty.
    -- In this case, we have to look at the second line to determine
    -- the indentation depth.
    if T.null firstLine then do
        spacesBeforeFirstLine <- spaces
        firstLine' <- restOfLine
        let indent = T.length spacesBeforeFirstLine
        lines <- trailingIndentedLines indent
        pure (key, firstLine' : lines)
    -- If the first line is *not* empty, we can determine the indentation
    -- depth by calculating how many characters came before it.
    else do
        let indent = T.length spacesBeforeKey + T.length key + 1 + T.length spacesAfterKey
        lines <- trailingIndentedLines indent
        pure (key, firstLine : lines)

    where
        trailingIndentedLines :: Int -> Parser [Text]
        trailingIndentedLines indent = many $ try $ indentedLine indent

indentedLine :: Int -> Parser Text
indentedLine indent = do
    void $ chunk $ T.replicate indent " "
    restOfLine

spaces :: Parser Text
spaces = takeWhileP Nothing (== ' ')

-- | Parse until next @\n@, return text before that.
restOfLine :: Parser Text
restOfLine = do
    s <- takeWhileP (Just "rest of line") (/= '\n')
    eolOrEof
    pure s

eolOrEof :: Parser ()
eolOrEof = void (single '\n') <|> eof
