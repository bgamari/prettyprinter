{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where



import qualified Data.ByteString.Lazy  as BSL
import qualified Data.Text             as T
import           Data.Text.PgpWordlist
import           Data.Word

import Data.Text.Prettyprint.Doc
import Data.Text.Prettyprint.Doc.Render.Text

import Test.Tasty
import Test.Tasty.QuickCheck

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
import Data.Semigroup
#endif



main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Fusion"
    [ testProperty "Shallow fusion does not change rendering"
                   (fusionDoesNotChangeRendering Shallow)
    , testProperty "Deep fusion does not change rendering"
                   (fusionDoesNotChangeRendering Deep)
    ]

fusionDoesNotChangeRendering :: FusionDepth -> Property
fusionDoesNotChangeRendering depth
  = forAll document (\doc ->
        let rendered = render doc
            renderedFused = render (fuse depth doc)
        in counterexample (mkCounterexample rendered renderedFused)
                          (render doc == render (fuse depth doc)) )
  where
    render = renderStrict . layoutPretty defaultLayoutOptions
    mkCounterexample rendered renderedFused
      = (T.unpack . render . vsep)
            [ "Unfused and fused documents render differently!"
            , "Unfused:"
            , indent 4 (pretty rendered)
            , "Fused:"
            , indent 4 (pretty renderedFused) ]

newtype RandomDoc ann = RandomDoc (Doc ann)

instance Arbitrary (RandomDoc ann) where
    arbitrary = fmap RandomDoc document

document :: Gen (Doc ann)
document = (dampen . frequency)
    [ (20, content)
    , (1, newlines)
    , (1, nestingAndAlignment)
    , (1, grouping)
    , (20, concatenationOfTwo)
    , (5, concatenationOfMany)
    , (1, enclosingOfOne)
    , (1, enclosingOfMany) ]

content :: Gen (Doc ann)
content = frequency
    [ (1, pure emptyDoc)
    , (10, do word <- choose (minBound, maxBound :: Word8)
              let pgp8Word = toText (BSL.singleton word)
              pure (pretty pgp8Word) )
    , (1, (fmap pretty . elements . mconcat)
              [ ['a'..'z']
              , ['A'..'Z']
              , ['0'..'9']
              , "…_[]^!<>=&@:-()?*}{/\\#$|~`+%\"';" ] )
    ]

newlines :: Gen (Doc ann)
newlines = frequency
    [ (1, pure line)
    , (1, pure line')
    , (1, pure softline)
    , (1, pure softline')
    , (1, pure hardline) ]

nestingAndAlignment :: Gen (Doc ann)
nestingAndAlignment = frequency
    [ (1, nest   <$> arbitrary <*> concatenationOfMany)
    , (1, group  <$> document)
    , (1, hang   <$> arbitrary <*> concatenationOfMany)
    , (1, indent <$> arbitrary <*> concatenationOfMany) ]

grouping :: Gen (Doc ann)
grouping = frequency
    [ (1, align  <$> document)
    , (1, flatAlt <$> document <*> document) ]

concatenationOfTwo :: Gen (Doc ann)
concatenationOfTwo = frequency
    [ (1, (<>) <$> document <*> document)
    , (1, (<+>) <$> document <*> document) ]

concatenationOfMany :: Gen (Doc ann)
concatenationOfMany = frequency
    [ (1, hsep    <$> listOf document)
    , (1, vsep    <$> listOf document)
    , (1, fillSep <$> listOf document)
    , (1, sep     <$> listOf document)
    , (1, hcat    <$> listOf document)
    , (1, vcat    <$> listOf document)
    , (1, fillCat <$> listOf document)
    , (1, cat     <$> listOf document) ]

enclosingOfOne :: Gen (Doc ann)
enclosingOfOne = frequency
    [ (1, squotes  <$> document)
    , (1, dquotes  <$> document)
    , (1, parens   <$> document)
    , (1, angles   <$> document)
    , (1, brackets <$> document)
    , (1, braces   <$> document) ]

enclosingOfMany :: Gen (Doc ann)
enclosingOfMany = frequency
    [ (1, encloseSep <$> document <*> document <*> pure ", " <*> listOf document)
    , (1, list       <$> listOf document)
    , (1, tupled     <$> listOf document) ]

-- QuickCheck 2.8 does not have 'scale' yet, so for compatibility with older
-- releases we hand-code it here
dampen :: Gen a -> Gen a
dampen gen = sized (\n -> resize ((n*2) `quot` 3) gen)