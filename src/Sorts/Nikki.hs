{-# language NamedFieldPuns, ViewPatterns, MultiParamTypeClasses,
    FlexibleInstances, DeriveDataTypeable, ScopedTypeVariables #-}

module Sorts.Nikki (sorts, addBatteryPower, modifyNikki, nikkiMass, walkingVelocity) where


import Prelude hiding (lookup)

import Data.Map (Map, toList, fromList, (!), lookup)
import Data.Abelian
import Data.Generics
import Data.Initial
import Data.Foldable hiding (toList)

import System.FilePath

import Graphics.Qt as Qt hiding (rotate, scale)

import Sound.SFML

import qualified Physics.Chipmunk as CM
import Physics.Chipmunk hiding (position, Position)
import qualified Physics.Hipmunk as Hip

import Paths
import Utils

import Base.Constants
import Base.Animation
import Base.Pixmap
import Base.Types
import Base.Debugging

import Object

import Sorts.Nikki.Types
import Sorts.Nikki.Configuration
import Sorts.Nikki.Initialisation
import Sorts.Nikki.State
import Sorts.Nikki.Control
import Sorts.Nikki.JumpingImpulse


sorts :: IO [Sort_]
sorts = do
    pixmaps <- loadPixmaps
    psize <- fmap fromIntegral <$> sizeQPixmap (pixmap $ defaultPixmap pixmaps)
    soundFile <- getDataFileName (soundDir </> "nikki/jump.wav")
    jumpSound <- newPolySound soundFile 4
    let r = NSort pixmaps jumpSound
    return [Sort_ r]

loadPixmaps :: IO (Map String [Pixmap])
loadPixmaps = do
    fromList <$> (fmapM load $ toList statePixmaps)
  where
    load :: (String, Int) -> IO (String, [Pixmap])
    load (name, n) = do
        pixmaps <- mapM (getDataFileName >>>> loadPixmap 1) $ map (mkPngPath name) [0..n]
        return (name, pixmaps)

mkPngPath name n = nikkiPngDir </> name ++ "_0" ++ show n <.> "png"

nikkiPngDir = pngDir </> "nikki"

defaultPixmap :: Map String [Pixmap] -> Pixmap
defaultPixmap pixmaps = head (pixmaps ! "wait_left")


modifyNikki :: (Nikki -> Nikki) -> Scene Object_ -> Scene Object_
modifyNikki f scene =
    modifyMainlayerObjectByIndex inner (nikki (mode scene)) scene
  where
    inner :: Object_ -> Object_
    inner (Object_ s o) =
        Object_ s' o'
      where
        Just s' = cast s
        Just castO = cast o
        o' = f castO


instance Sort NSort Nikki where

    sortId _ = SortId "nikki"

    freeSort (NSort pixmaps sound) = do
        fmapM_ (fmapM_ freePixmap) pixmaps
        freePolySound sound

    size sort =
        if pixSize /= nikkiSize
        then error "nikkis pixmaps have the wrong size"
        else nikkiSize
      where
        pixSize = pixmapSize $ defaultPixmap $ pixmaps sort

    sortRender sort ptr _ =
        renderPixmapSimple ptr (defaultPixmap $ pixmaps sort)

    initialize sort (Just space) editorPosition Nothing = do
        let (surfaceVelocityShapeType, otherShapes, baryCenterOffset) = mkPolys
            pos = qtPosition2Vector (editorPosition2QtPosition sort editorPosition)
                    +~ baryCenterOffset

        chip <- CM.initChipmunk space (bodyAttributes pos) (surfaceVelocityShapeType : otherShapes)
                    baryCenterOffset

        let surfaceVelocityShape = head $ shapes chip

        return $ Nikki
            chip
            surfaceVelocityShape
            initial
            0
            0

    immutableCopy n@Nikki{chipmunk} = CM.immutableCopy chipmunk >>= \ new -> return n{chipmunk = new}

    chipmunks = return . chipmunk

    getControlledChipmunk = chipmunk

    updateNoSceneChange sort mode now contacts cd nikki = inner nikki
      where
        inner =
            updateState now contacts cd >>>>
            fromPure (updateStartTime now (state nikki)) >>>>
            controlNikki now contacts cd sort >>>>
--             passThrough (debugNikki now contacts) >>>>
            return

    render nikki sort ptr offset now = do
        let pixmap = pickPixmap now sort nikki
        renderChipmunk ptr offset pixmap (chipmunk nikki)
        renderClouds ptr offset now sort (action $ state nikki)


pickPixmap :: Seconds -> NSort -> Nikki -> Pixmap
pickPixmap now sort nikki =
    let (name, frameTimes_) = frameTimes $ state nikki
        m = lookup name (pixmaps sort)
    in case m of
        Just pixmapList ->
            pickAnimationFrameNonLooping pixmapList frameTimes_ (now - startTime nikki)
        Nothing -> es "problem finding pixmaps in Nikki: " name

renderClouds :: Ptr QPainter -> Offset Double -> Seconds -> NSort -> Action -> IO ()
renderClouds ptr offset now sort (WallSlide _ _ clouds) =
    fmapM_ render clouds
  where
    render cloud = do
        let mPixmap = case lookup "dust" (pixmaps sort) of
                Just pixmapList -> do
                    pickLimitedAnimationFrame pixmapList cloudFrameTimes (now - creationTime cloud)
        case mPixmap of
            Just pixmap ->
                renderPixmap ptr offset (cloudPosition cloud) Nothing pixmap
            Nothing -> return ()
renderClouds _ _ _ _ _ = return ()

-- debugging

debugNikki :: Seconds -> Contacts -> Nikki -> IO ()
debugNikki now contacts nikki = do
    addDebugging $ \ ptr offset -> do
      resetMatrix ptr
      drawText ptr (Position 30 30) False $ show $ action $ state nikki
      forM_ (nikkiCollisions contacts) $ \ (NikkiCollision shape normal _) -> do
        resetMatrix ptr
        translate ptr offset
        translateVector ptr =<< getPosition (chipmunk nikki)
        drawAngle ptr green $ toUpAngle normal

debugNikki now contacts nikki = do
    position <- getPosition $ chipmunk nikki
    nikkiVelocity <- get $ velocity $ body $ chipmunk nikki
    let mContact = jumpAngle $ getContactNormals contacts
    case mContact of
      Nothing -> do
        addDebugging $ \ ptr offset -> do
            resetMatrix ptr
            drawText ptr (Position 30 30) False "debugging"
            translate ptr offset
            translateVector ptr position
            drawVector ptr red nikkiVelocity

      Just (shape, contactAngle) -> do
        collisionObjectVelocity <- get (Hip.velocity (Hip.body shape))
        addDebugging $ \ ptr offset -> do
            resetMatrix ptr
            drawText ptr (Position 30 30) False "debugging"
            translate ptr offset
            translateVector ptr position
            let velocity = nikkiVelocity -~ collisionObjectVelocity
            drawVector ptr red velocity
            drawAngle ptr yellow contactAngle

            let calculation = calculate collisionObjectVelocity contactAngle nikkiVelocity
            drawVector ptr black (staticImpulse calculation)
            drawVector ptr blue $ wallVelocity calculation
            drawVectorAddition ptr (red, green, magenta)
                velocity
                (correctedImpulse calculation)



drawVector :: Ptr QPainter -> Color -> Vector -> IO ()
drawVector ptr color v = do
    setPenColor ptr color 3
    drawLine ptr zero $ vector2QtPosition $ scale v 0.25

drawVectorAddition :: Ptr QPainter -> (Color, Color, Color) -> Vector -> Vector -> IO ()
drawVectorAddition ptr (aColor, bColor, cColor) a b = do
    drawVector ptr aColor a
    translateVector ptr $ scale a 0.25
    drawVector ptr bColor b
    translateVector ptr $ scale (negateAbelian a) 0.25
    drawVector ptr cColor (a +~ b)

drawAngle ptr color angle = drawVector ptr color $ flip scale 200 $ fromUpAngle angle
