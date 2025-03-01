#loader crafttweaker reloadable
# Author: WaitingIdly

import crafttweaker.event.PlayerInteractEntityEvent;
import crafttweaker.event.PlayerInteractBlockEvent;
import crafttweaker.event.BlockBreakEvent;
import crafttweaker.event.CommandEvent;
import crafttweaker.world.IBlockPos;
import crafttweaker.block.IBlock;
import crafttweaker.entity.IEntityEquipmentSlot;
import crafttweaker.player.IPlayer;
import crafttweaker.data.IData;
import crafttweaker.item.IItemStack;
import mods.zenutils.command.CommandUtils;
import mods.zenutils.I18n;

static astralTiers as string[] = [
    "BASIC_CRAFT",
    "ATTUNEMENT",
    "CONSTELLATION",
    "RADIANCE"
] as string[];

function progressAstral(player as IPlayer, level as int) {
    val data as IData = player.data.divine_journey_2;

    val progressingFrom = (!isNull(data) && !isNull(data.astral_level)) ? data.astral_level : -1;

    // Only progress them up to the tier once, otherwise it spams the chat.
    // This cannot be done via simply changing the tier in the playerdata because Astral stores its data in its own file
    if (level > progressingFrom) {
        server.commandManager.executeCommandSilent(server, "/astralsorcery research " + player.name + " " + astralTiers[level]);
        player.update({ divine_journey_2: { astral_level: level } });
    }
}

// Return the hand the target item is in, ignoring metadata. Returns `head` if in neither hand.
function whatHand(player as IPlayer, target as IItemStack) as IEntityEquipmentSlot {
    if (!isNull(player.mainHandHeldItem) && player.mainHandHeldItem.definition.id == target.definition.id) {
        return crafttweaker.entity.IEntityEquipmentSlot.mainHand();
    }
    if (!isNull(player.offHandHeldItem) && player.offHandHeldItem.definition.id == target.definition.id) {
        return crafttweaker.entity.IEntityEquipmentSlot.offhand();
    }
    // Since Crafttweaker hasn't implemented IAny/multi-typed returns so this could be null, using `head` as a workaround
    // This isn't best practices
    return crafttweaker.entity.IEntityEquipmentSlot.head();
}

// Add Ender Core activations to all dimensions
function activateEnderCore(player as IPlayer) as void {
    val goal = <enderutilities:enderpart>;

    var target as IEntityEquipmentSlot = whatHand(player, goal);
    if (target == crafttweaker.entity.IEntityEquipmentSlot.head()) return;
    var item as IItemStack = player.getItemInSlot(target);

    val meta as int = item.metadata;

    // 10, 11, and 12 are the valid meta values for Inactive Ender Cores.
    if (meta >= 10 && meta <= 12) {
        // Change the item from uncharged to charged
        player.setItemToSlot(target, goal.definition.makeStack(meta + 5) * item.amount);
    }
}

function removeItemFromHand(player as IPlayer, item as IItemStack) {
    if (!isNull(player.mainHandHeldItem) && item.matches(player.mainHandHeldItem)) {
        player.setItemToSlot(crafttweaker.entity.IEntityEquipmentSlot.mainHand(), null);
    } else if (!isNull(player.offHandHeldItem) && item.matches(player.offHandHeldItem)) {
        player.setItemToSlot(crafttweaker.entity.IEntityEquipmentSlot.offhand(), null);
    }
}

events.onPlayerInteractBlock(function(e as PlayerInteractBlockEvent) {
    if (e.player.world.isRemote()) {
        return;
    }

    // The Uncrafting Table should never be openable, to prevent a duplication bug
    if (e.block.definition.id == <twilightforest:uncrafting_table>.definition.id) {
        e.cancel();
    }

    // Grant the user the Astral Sorcery Knowledge to use the table they just right clicked on.
    if (e.block.definition.id == <astralsorcery:blockaltar>.definition.id) {
        progressAstral(e.player, e.block.meta);
    }

    // Disable individual Elemental Inscription Tools
    // Without the `whatHand` part and just using `e.item` it constantly caused NPEs.
    if (whatHand(e.player, <bloodmagic:inscription_tool>) != crafttweaker.entity.IEntityEquipmentSlot.head())  {
        e.player.sendStatusMessage(format.lightPurple("Elemental Inscription Tools cannot be used outside of an Elemental Diviner!") +
        format.gold("\nDurability not actually consumed, just a desync."));
        e.cancel();
    }

    // Activate the held ender core if the target block was a stabilized end crystal
    if (e.block.definition.id == <contenttweaker:stabilized_end_crystal>.definition.id) {
        activateEnderCore(e.player);
    }

    // DivineRPG always removes an item from the main hand when using one of these boss spawning items.
    // https://github.com/DivineRPG/DivineRPG/blob/1a3b87972f9a0ccf7686723541d9cae2ae2b6d24/src/main/java/divinerpg/objects/items/twilight/ItemBossSpawner.java#L61
    // This contains code which does virtually the same thing, but removes the correct item.
    if (<divinerpg:horde_horn>.matches(e.item)) {
        if (e.dimension == 1) {
            val spawnLocation as IBlockPos = e.position.getOffset(crafttweaker.world.IFacing.up(), 1);
            if (e.world.isAirBlock(spawnLocation)) {
                // Sounds aren't accessible via crafttweaker, so we run a command instead
                // Note that this command is modified from the original - the original is on channel `master` and with a volume of 20
                server.commandManager.executeCommandSilent(server, "/playsound divinerpg:ayeraco_spawn hostile " + e.player.name + " " + e.x + " " + e.y + " " + e.z + " 5 1");
                e.world.setBlockState(<blockstate:divinerpg:ayeraco_spawn>, spawnLocation);
                removeItemFromHand(e.player, <divinerpg:horde_horn>);
            } else {
                e.player.sendChat("§bFailed to spawn - please use in open air.");
            }
        } else {
            e.player.sendChat("§b" + I18n.format("message.ayeraco_horde"));
        }
        e.cancel();
    } else if (<divinerpg:call_of_the_watcher>.matches(e.item)) {
        if (e.dimension == -1) {
            <entity:divinerpg:the_watcher>.spawnEntity(e.world, e.position);
            removeItemFromHand(e.player, <divinerpg:call_of_the_watcher>);
        } else {
            e.player.sendChat("§b" + I18n.format("message.watcher"));
        }
        e.cancel();
    } else if (<divinerpg:infernal_flame>.matches(e.item)) {
        if (e.dimension == -1) {
            <entity:divinerpg:king_of_scorchers>.spawnEntity(e.world, e.position);
            removeItemFromHand(e.player, <divinerpg:infernal_flame>);
        } else {
            e.player.sendChat("§b" + I18n.format("message.king_of_scorchers"));
        }
        e.cancel();
    } else if (<divinerpg:mysterious_clock>.matches(e.item)) {
        if (e.dimension == 0) {
            <entity:divinerpg:ancient_entity>.spawnEntity(e.world, e.position);
            removeItemFromHand(e.player, <divinerpg:mysterious_clock>);
        } else {
            e.player.sendChat("§b" + I18n.format("message.ancient_entity"));
        }
        e.cancel();
    }
});

events.onPlayerInteractEntity(function(e as PlayerInteractEntityEvent) {
    if (e.player.world.isRemote()) {
        return;
    }

    if (isNull(e.target.definition)) {
        return;
    }

    val id = e.target.definition.id;

    // Disable Bewitchment Demon Trading
    if (id == "bewitchment:demon" || id == "bewitchment:demoness") {
        e.cancel();
        #e.player.sendChat("What's a fallen angel doing trying to make a deal with such a foul creature?");
    }

    // Activate the held ender core if the target entity was an end crystal
    if (id == "minecraft:ender_crystal") {
        activateEnderCore(e.player);
    }
});

// Fixing Immersive Engineering's Engineers Workbench voiding contents when broken on the wrong side
events.onBlockBreak(function(e as BlockBreakEvent) {
    if (e.world.isRemote()) {
        return;
    }
    // If its not the Engineers Workbench, cancel out
    if (
        !(e.world.getBlock(e.position).definition.id == <immersiveengineering:wooden_device0:2>.asBlock().definition.id &&
        e.world.getBlock(e.position).meta == <immersiveengineering:wooden_device0:2>.asBlock().meta)
    ) {
        return;
    }

    var pos as IBlockPos = e.position;
    var target as IBlockPos = pos;

    // If its not the dummy block, IE already drops it correctly. Otherwise, use its internal facing attribute
    // to figure out which block stores the inventory, and save its position.
    if (!isNull(e.world.getBlock(pos).data)) {
        if (e.world.getBlock(pos).data.dummy == 0) return;
        else {
            target = e.position.getOffset(
                crafttweaker.world.IFacing.fromString(
                    // UP and DOWN are the 0 and 1 values of facing, so offset it by -2
                    (["WEST", "EAST", "SOUTH", "NORTH"] as string[])[e.world.getBlock(pos).data.facing - 2]
                ),
                1
            );
        }
    }

    // Then, run though all the items and drop them in world, with the appropriate quanties and tags.
    for drop in e.world.getBlock(target).data.inventory.asList() {
        var item as IItemStack = itemUtils.getItem(drop.id, drop.Damage) * drop.Count;
        if (!isNull(drop.tag)) item = item.withTag(drop.tag);
        e.world.spawnEntity(item.createEntityItem(e.world, target));

    }
});

events.onCommand(function(e as CommandEvent) {
    val command = e.command;

    if(isNull(command)) {
        return;
    }

    // If its its the Astral Sorcery reset command, we reset the players internal data
    if ((command.name == "astralsorcery") && (e.parameters.length > 0) && (e.parameters[0] == "reset")) {
        val player = e.commandSender.world.getPlayerByName(e.parameters[1]);
        if (!isNull(player)) {
            player.update({ divine_journey_2: { astral_level: -1 } });
        }
    }
});
