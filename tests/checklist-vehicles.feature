# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_garages — Vehicles

  @kora_garages @checklist @checklist:kora_garages:open-public-garage @cat:vehicles
  Scenario: Open a public garage
    """
    Checklist test: Go to Legion Square, Pink Cage Motel or Sandy Shores parking, Alt-target the zone and pick 'Open <garage>'; vehicles panel opens.
    """
    When I go to "legion_square"
    And I manually: Alt-target the garage zone and pick 'Open <garage>'
    Then the "qbgarages:garage" app opens
    When I manually: go to Pink Cage Motel or Sandy Shores parking
    And I manually: Alt-target the garage zone and pick 'Open <garage>'
    Then the "qbgarages:garage" app should be open

  @kora_garages @checklist @checklist:kora_garages:garage-vehicle-list @cat:vehicles
  Scenario: Vehicle list with state and details
    """
    Checklist test: Open a garage: your garaged vehicles are listed with model, plate, fuel/health; the panel shows a count badge.
    """
    When I manually: open a garage I own vehicles in
    Then the "qbgarages:garage" app should be open
    And I confirm: my garaged vehicles are listed with model, plate, fuel and health
    And I confirm: the panel shows a count badge

  @kora_garages @checklist @checklist:kora_garages:take-out-vehicle @cat:vehicles @manual
  Scenario: Take a vehicle out
    """
    Checklist test: Pick a garaged vehicle in the panel: it spawns at a free spawn point with stored fuel, health and look.
    """
    When I manually: open a garage and pick a garaged vehicle in the panel
    Then I confirm: the vehicle spawns at a free spawn point
    And I confirm: the vehicle has its stored fuel, health and look

  @kora_garages @checklist @checklist:kora_garages:store-vehicle @cat:vehicles
  Scenario: Store a vehicle
    """
    Checklist test: Drive your out vehicle within 12m of the garage and select it in the panel to store it; vehicle is deleted and state becomes garaged.
    """
    When I manually: drive my out vehicle within 12m of the garage
    And I manually: open the garage panel and select the vehicle to store it
    Then the vehicle should be deleted
    And I confirm: the vehicle is listed as garaged in the panel

  @kora_garages @checklist @checklist:kora_garages:store-far-away @cat:vehicles @manual
  Scenario: Store refused when too far
    """
    Checklist test: Try to store a vehicle far from the garage or someone else's vehicle: server refuses with a message.
    """
    When I manually: try to store a vehicle far from the garage
    Then I confirm: the server refuses with a message
    When I manually: try to store someone else's vehicle at a garage
    Then I confirm: the server refuses with a message

  @kora_garages @checklist @checklist:kora_garages:spawn-clearance @cat:vehicles @manual
  Scenario: Spawn point blocked
    """
    Checklist test: Block spawn points with vehicles and take out another: next free point is used or a clearance error shows.
    """
    When I manually: block the garage spawn points with vehicles
    And I manually: take out another vehicle from the garage panel
    Then I confirm: the next free spawn point is used or a clearance error shows

  @kora_garages @checklist @checklist:kora_garages:cosmetics-protected @cat:vehicles @manual
  Scenario: Looks preserved when parked
    """
    Checklist test: Preview paint, park the car and retrieve it: stored look is unchanged (cosmetics are not trusted from the client).
    """
    When I manually: preview a paint on my vehicle without buying it
    And I manually: park the car in a garage and retrieve it
    Then I confirm: the stored look is unchanged and the previewed paint is not applied

  @kora_garages @checklist @checklist:kora_garages:job-garage @cat:vehicles
  Scenario: Job garage (Mission Row Motor Pool)
    """
    Checklist test: As police on duty, open the Mission Row motor pool; other jobs or off-duty police do not see the option.
    """
    Given my job is "police"
    And I am on duty
    When I manually: go to the Mission Row motor pool and Alt-target the garage
    Then I confirm: the open garage option is available
    When I manually: switch to another job and check the Mission Row motor pool
    Then I confirm: the option is not shown
    When I manually: go off duty as police and check the Mission Row motor pool
    Then I confirm: the option is not shown

  @kora_garages @checklist @checklist:kora_garages:gang-garage @cat:vehicles
  Scenario: Gang garage (Forum Drive Lockup)
    """
    Checklist test: As a ballas member open the gang garage; non-members do not get the interaction.
    """
    Given my gang is "ballas"
    When I manually: go to the Forum Drive Lockup and Alt-target the garage
    Then the "qbgarages:garage" app opens
    When I manually: ask a second player who is not a ballas member to approach the Forum Drive Lockup
    Then I confirm: the other player does not get the interaction

  @kora_garages @checklist @checklist:kora_garages:impound-lot @cat:vehicles
  Scenario: Impound lot release
    """
    Checklist test: Open the Davis Impound Lot with an impounded vehicle; it shows the fee, 'Pay $X & release' takes the money and spawns it.
    """
    Given my cash balance is 5000
    When I manually: go to the Davis Impound Lot with an impounded vehicle and open it
    Then I confirm: the panel shows the fee
    When I manually: select 'Pay $X & release'
    Then I confirm: the fee is taken from my money
    And I confirm: the vehicle spawns

  @kora_garages @checklist @checklist:kora_garages:impound-no-money @cat:vehicles
  Scenario: Impound release without funds
    """
    Checklist test: Release an impounded vehicle without enough money: error 'You need $X to release this vehicle'.
    """
    Given my cash balance is 0
    And my bank balance is 0
    When I manually: open the Davis Impound Lot and try to release an impounded vehicle
    Then I should see a notification containing "You need $"
    And I should see an error notification

  @kora_garages @checklist @checklist:kora_garages:impound-no-store @cat:vehicles @manual
  Scenario: Cannot store at impound or from public garage
    """
    Checklist test: Try to store a car at the impound lot, and to take an impounded car out of a public garage: both refused.
    """
    When I manually: try to store a car at the impound lot
    Then I confirm: the store is refused
    When I manually: try to take an impounded car out of a public garage
    Then I confirm: the take-out is refused

  @kora_garages @checklist @checklist:kora_garages:house-garages @cat:vehicles @manual
  Scenario: House/property garages
    """
    Checklist test: Use a house garage (from housing) or one registered via RegisterPropertyGarage; only people with property permission can list/store/retrieve.
    """
    When I manually: open a house garage or one registered via RegisterPropertyGarage with property permission
    Then I confirm: I can list, store and retrieve vehicles
    When I manually: ask a second player without property permission to try to list, store and retrieve
    Then I confirm: the other player is refused for list, store and retrieve

  @kora_garages @checklist @checklist:kora_garages:garage-blips @cat:vehicles @manual
  Scenario: Garage map blips
    """
    Checklist test: Check the map: Garage, Job Garage, Gang Garage and Impound blips appear with their colours.
    """
    When I manually: open the map
    Then I confirm: Garage, Job Garage, Gang Garage and Impound blips appear with their colours

  @kora_garages @checklist @checklist:kora_garages:garage-markers @cat:vehicles @manual
  Scenario: Optional ground markers
    """
    Checklist test: With Config.markers.enabled, approach a usable garage within 15m: a ground marker is drawn and disappears when you leave.
    """
    When I manually: approach a usable garage within 15m
    Then I confirm: a ground marker is drawn (only applies when Config.markers.enabled; otherwise mark Pass if nothing happens)
    When I manually: walk away from the garage
    Then I confirm: the ground marker disappears

  @kora_garages @checklist @checklist:kora_garages:storeall-command @cat:vehicles @needs:admin
  Scenario: garage:storeAll admin command
    """
    Checklist test: As admin run garage:storeAll [minutes]: warns all players with countdown then removes all vehicles and sets them garaged.
    """
    When I run the command "/garage:storeAll"
    Then I confirm: all players are warned with a countdown
    And I confirm: after the countdown all vehicles are removed and set to garaged

  @kora_garages @checklist @checklist:kora_garages:restart-recovery @cat:vehicles
  Scenario: Vehicles left out return to garage
    """
    Checklist test: After server restart vehicles that were out (state out) are shown as garaged again.
    """
    When I manually: leave a vehicle out of the garage and ask a Mod to restart the server
    And I manually: open the garage panel
    Then the "qbgarages:garage" app should be open
    And I confirm: the vehicle that was out is shown as garaged again

  @kora_garages @checklist @checklist:kora_garages:open-garage-export @cat:vehicles @needs:admin
  Scenario: openGarage export
    """
    Checklist test: Call exports.kora_garages:openGarage(id) from a client script: the garage panel opens, or an unavailable error is returned.
    """
    When I manually: as an admin, run the client-side code command /crun with print(exports.kora_garages:openGarage('<id of an existing garage>')), using a real garage id
    Then the "qbgarages:garage" app opens
    And I confirm: the F8 console prints true
    When I manually: as an admin, run /crun with print(exports.kora_garages:openGarage('<an id that matches no garage>'))
    Then I confirm: the F8 console prints false followed by an error message and no garage panel opens
