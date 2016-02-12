{-# LANGUAGE OverloadedStrings #-}

module Text.Marquee.Parser.Common where

import Control.Applicative
import Control.Monad

import Data.Char (isControl, isPunctuation, isSpace, isSymbol)
import Data.Text (Text())
import qualified Data.Text as T

import Data.Attoparsec.Text as Atto
import Data.Attoparsec.Combinator

-- Useful parsers

lineEnding :: Parser ()
lineEnding = endOfLine

lineEnding_ :: Parser ()
lineEnding_ = endOfLine <|> endOfInput

whitespace :: Parser Char
whitespace = satisfy isWhitespace

linespace :: Parser Char
linespace = satisfy isLinespace

emptyLine :: Parser ()
emptyLine = skipWhile isLinespace *> lineEnding_

optIndent :: Parser String
optIndent = atMostN 3 (char ' ')

printable :: Parser Char
printable = satisfy (not . isSpace)

punctuation :: Parser Char
punctuation = satisfy isPunctuation

control :: Parser Char
control = satisfy isControl

next :: Parser a -> Parser a
next p = skipWhile isLinespace *> p

escape :: Char -> Parser Char
escape c = char '\\' *> char c

escaped :: Parser Char
escaped = char '\\' *> satisfy (\c -> isPunctuation c || isSymbol c)

oneOf :: [Char] -> Parser Char
oneOf cs = satisfy (\c -> c `elem` cs)

noneOf :: [Char] -> Parser Char
noneOf cs = satisfy (\c -> c `notElem` cs)

linkLabel :: Parser Text
linkLabel = between (char '[') (char ']') (takeEscapedWhile (`elem` escapable) (`notElem` escapable))
  where escapable = "[]" :: String

linkDestination :: Parser Text
linkDestination =
  between (char '<') (char '>') takeBetween
  <|>
  T.concat <$> many1 (takeDest <|> parens)
  where parens   = do
          open <- string "("
          content <- takeDest <|> return ""
          close <- string ")"
          return $ T.concat [open, content, close]
        takeBetween = takeEscapedWhile
                      (\c -> isPunctuation c || isSymbol c)
                      (\c -> not $ isWhitespace c || c == '<' || c == '>')
        takeDest    = takeEscapedWhile1
                      (\c -> isPunctuation c || isSymbol c)
                      (\c -> not $ isWhitespace c || isControl c || c == '(' || c == ')')

linkTitle :: Parser Text
linkTitle = titleOf '"' '"' <|> titleOf '\'' '\'' <|> titleOf '(' ')'
  where titleOf :: Char -> Char -> Parser Text
        titleOf open close =
          between
            (char open)
            (char close)
            (takeEscapedWhile (`elem` escapable) (`notElem` escapable))
          where escapable = [open, close]

-- Combinators

takeEscapedWhile :: (Char -> Bool) -> (Char -> Bool) -> Parser Text
takeEscapedWhile x y = takeEscapedWhile1 x y <|> pure ""

takeEscapedWhile1 :: (Char -> Bool) -> (Char -> Bool) -> Parser Text
takeEscapedWhile1 isEscapable while = do
  x <- normal1 <|> escaped
  xs <- many escaped
  return $ T.concat (x:xs)
  where isValid c = c /= '\\' && while c
        normal    = Atto.takeWhile isValid
        normal1   = Atto.takeWhile1 isValid
        escaped   = do
          x <- (char '\\' *> satisfy isEscapable) <|> char '\\'
          xs <- normal
          return $ T.cons x xs

between :: Parser open -> Parser close -> Parser a -> Parser a
between open close p = open *> p <* close

optionMaybe :: Alternative f => f a -> f (Maybe a)
optionMaybe p = option Nothing $ Just <$> p

manyN :: Int -> Parser a -> Parser [a]
manyN n p
  | n <= 0 = return []
  | otherwise = liftM2 (++) (count n p) (many p)

manyTill1 :: Alternative f => f a -> f b -> f [a]
manyTill1 p end = liftA2 (:) p (manyTill p end)

atMostN :: Int -> Parser a -> Parser [a]
atMostN n p
  | n <= 0 = count 0 p
  | otherwise = count n p <|> atMostN (n - 1) p

atMostN1 :: Int -> Parser a -> Parser [a]
atMostN1 n p
  | n <= 1 = count 1 p
  | otherwise = count n p <|> atMostN1 (n - 1) p

-- Useful functions

isWhitespace :: Char -> Bool
isWhitespace c = isSpace c

isLinespace :: Char -> Bool
isLinespace c = isSpace c && (not . isLineEnding) c

isLineEnding :: Char -> Bool
isLineEnding c = c == '\n' || c == '\r'

isPrintable :: Char -> Bool
isPrintable = not . isSpace
