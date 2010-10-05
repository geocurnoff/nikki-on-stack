{-# language NamedFieldPuns #-}

module Object.Contacts (
    MyCollisionType(..),
    watchedContacts,

    Contacts(..),
    nikkiTouchesTerminal,
  ) where


import Data.Set as Set hiding (map)
import Data.Array.Storable
import Data.Initial

import Physics.Chipmunk

import Base.Types


nikkiSolidCollisionTypes :: [NikkiCollisionType]
nikkiSolidCollisionTypes = [NikkiHead, NikkiFeet, NikkiLeftPaw, NikkiRightPaw]

solidCollisionTypes :: [MyCollisionType]
solidCollisionTypes = [
    TileCT,
    RobotCT,
    FallingTileCT
  ]


-- initial in the sense that nothing collides
instance Initial Contacts where
    initial = Contacts [] False False False False empty empty empty empty


-- * setter (boolean to True)

addNikkiContacts :: Vector -> Contacts -> Contacts
addNikkiContacts v c =
    c{nikkiContacts = (v : nikkiContacts c)}

setNikkiFeetTouchGround :: Contacts -> Contacts
setNikkiFeetTouchGround c = c{nikkiFeetTouchGround = True}

setNikkiLeftPawTouchesGround :: Contacts -> Contacts
setNikkiLeftPawTouchesGround c = c{nikkiLeftPawTouchesGround = True}

setNikkiRightPawTouchesGround :: Contacts -> Contacts
setNikkiRightPawTouchesGround c = c{nikkiRightPawTouchesGround = True}

setNikkiTouchesLaser :: Contacts -> Contacts
setNikkiTouchesLaser c = c{nikkiTouchesLaser = True}

addTrigger :: Shape -> Contacts -> Contacts
addTrigger s c = c{triggers = insert s (triggers c)}

addTerminal :: Shape -> Contacts -> Contacts
addTerminal terminalShape c@Contacts{terminals} =
    c{terminals = insert terminalShape terminals}

nikkiTouchesTerminal :: Contacts -> Bool
nikkiTouchesTerminal = not . Set.null . terminals

addBattery :: Shape -> Contacts -> Contacts
addBattery batteryShape c =
    c{batteries = insert batteryShape (batteries c)}

addFallingTileContact :: Shape -> Contacts -> Contacts
addFallingTileContact fallingTileShape contacts =
    contacts{fallingTiles = insert fallingTileShape (fallingTiles contacts)}



watchedContacts :: [Callback MyCollisionType Contacts]
watchedContacts =
    -- normal contacts of nikki
    concatMap nikkiSolidCallbacks solidCollisionTypes ++
    [switchCallback] ++
    nikkiTerminalCallbacks ++
    map terminalSolidCallback solidCollisionTypes ++
    map batteryCallback nikkiSolidCollisionTypes ++
    [Callback (DontWatch BatteryCT TerminalCT) Permeable] ++
    nikkiFallingTilesCallbacks


nikkiSolidCallbacks solidCT = [
    Callback (FullWatch solidCT (NikkiCT NikkiHead) (\ _ _ -> addNikkiContacts)) Solid,
    Callback (FullWatch solidCT (NikkiCT NikkiFeet)
                (\ _ _ v -> setNikkiFeetTouchGround . addNikkiContacts v)) Solid,
    Callback (FullWatch solidCT (NikkiCT NikkiLeftPaw)
                (\ _ _ v -> setNikkiLeftPawTouchesGround . addNikkiContacts v)) Solid,
    Callback (FullWatch solidCT (NikkiCT NikkiRightPaw)
                (\ _ _ v -> setNikkiRightPawTouchesGround . addNikkiContacts v)) Solid
  ]

-- nikki stands in front of a terminal 
nikkiTerminalCallbacks = [
    Callback (Watch (NikkiCT NikkiHead) TerminalCT (\ _ t -> addTerminal t)) Permeable,
    Callback (DontWatch TerminalCT (NikkiCT NikkiFeet)) Permeable,
    Callback (DontWatch TerminalCT (NikkiCT NikkiLeftPaw)) Permeable,
    Callback (DontWatch TerminalCT (NikkiCT NikkiRightPaw)) Permeable
  ]

batteryCallback nikkiCT =
    Callback (Watch (NikkiCT nikkiCT) BatteryCT (\ _ b -> addBattery b)) Permeable

-- a trigger (in a switch) is activated
switchCallback =
    Callback (Watch TileCT TriggerCT (\ _ t -> addTrigger t)) Permeable

terminalSolidCallback solidCT =
    Callback (DontWatch TerminalCT solidCT) Permeable

-- contact with nikki and falling tiles
nikkiFallingTilesCallbacks = [
    Callback (FullWatch FallingTileCT (NikkiCT NikkiHead) (\ a b v -> addFallingTileContact a . addNikkiContacts v)) Solid,
    Callback (FullWatch FallingTileCT (NikkiCT NikkiFeet)
                (\ a b v -> addFallingTileContact a . setNikkiFeetTouchGround . addNikkiContacts v)) Solid,
    Callback (FullWatch FallingTileCT (NikkiCT NikkiLeftPaw)
                (\ a b v -> addFallingTileContact a . setNikkiLeftPawTouchesGround . addNikkiContacts v)) Solid,
    Callback (FullWatch FallingTileCT (NikkiCT NikkiRightPaw)
                (\ a b v -> addFallingTileContact a . setNikkiRightPawTouchesGround . addNikkiContacts v)) Solid
  ]


