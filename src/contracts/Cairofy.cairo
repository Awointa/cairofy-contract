// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0
#[starknet::contract]
pub mod CairofyV0 {
    use cairofy_contract::events::Events::{SongPriceUpdated, Song_Registered};
    use cairofy_contract::interfaces::ICairofy::ICairofy;
    use cairofy_contract::structs::Structs::Song;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::interface::{
        ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
        IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait,
    };
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    // use OwnableComponent::InternalTrait;

    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // External
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        // contract storage
        songs: Map<u64, Song>,
        song_count: u64,
        user_songs: Map<(ContractAddress, u64), bool>,
        user_song_count: Map<ContractAddress, u64>,
        user_song_ids: Map<(ContractAddress, u64), u64>,
        token_addr: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        // contract events
        Song_Registered: Song_Registered,
        SongPriceUpdated: SongPriceUpdated,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, token_addr: ContractAddress) {
        self.ownable.initializer(owner);
        self.token_addr.write(token_addr);
    }

    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.pause();
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.unpause();
        }
    }

    // Upgradeable
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    // contract Implementation
    #[abi(embed_v0)]
    impl CairofyImpl of ICairofy<ContractState> {
        fn register_song(
            ref self: ContractState,
            name: felt252,
            ipfs_hash: felt252,
            preview_ipfs_hash: felt252,
            price: u256,
            for_sale: bool,
        ) -> u64 {
            let caller = get_caller_address();

            assert!(name != 0, "Song name cannot be empty");
            assert!(ipfs_hash != 0, "Your song hash cannot be empty");
            assert!(preview_ipfs_hash != 0, "Your song preview hash cannot be empty");
            assert!(price > 0, "Price must be greater than 0");
            // Increment song count and return the new song ID
            let song_id = self.song_count.read() + 1;
            self.song_count.write(song_id);

            let song = Song {
                name: name,
                ipfs_hash: ipfs_hash,
                preview_ipfs_hash: preview_ipfs_hash,
                price: price,
                owner: caller,
                for_sale: for_sale,
            };
            //store the song in the contract storage
            self.songs.write(song_id, song);

            // Update user song mappings
            let user_song_count = self.user_song_count.read(caller);
            self.user_songs.write((caller, song_id), true);
            self.user_song_ids.write((caller, user_song_count), song_id);
            self.user_song_count.write(caller, user_song_count + 1);

            self.song_count.write(song_id);

            self
                .emit(
                    Event::Song_Registered(
                        Song_Registered {
                            song_id: song_id,
                            name: name,
                            ipfs_hash: ipfs_hash,
                            preview_ipfs_hash: preview_ipfs_hash,
                            price: price,
                            for_sale: for_sale,
                        },
                    ),
                );
            song_id
        }

        // TODO: Implement function to get detailed song info
        fn get_song_info(self: @ContractState, song_id: u64) -> Song {
            // Check if the song_id is valid
            let total_songs = self.song_count.read();
            assert!(song_id <= total_songs, "Song ID does not exist");

            // Read and return the song information from storage
            self.songs.read(song_id)
        }

        // TODO: Implement function to update the price of a song
        fn update_song_price(ref self: ContractState, song_id: u64, new_price: u256) {
            // Check if the song_id is valid
            let total_songs = self.song_count.read();
            assert!(song_id <= total_songs, "Song ID does not exist");
            let mut song = self.songs.read(song_id);
            assert!(new_price > 0, "Price must be greater than 0");

            //Verify that the caller is the owner of the song
            let caller = get_caller_address();
            assert!(song.owner == caller, "Only the owner can update the song price");

            let song = Song {
                name: song.name,
                ipfs_hash: song.ipfs_hash,
                preview_ipfs_hash: song.preview_ipfs_hash,
                price: new_price,
                owner: caller,
                for_sale: song.for_sale,
            };

            //store the song in the contract storage
            self.songs.write(song_id, song);

            self
                .emit(
                    Event::SongPriceUpdated(
                        SongPriceUpdated {
                            song_id: song_id,
                            name: song.name,
                            ipfs_hash: song.ipfs_hash,
                            preview_ipfs_hash: song.preview_ipfs_hash,
                            updated_price: song.price,
                            for_sale: song.for_sale,
                        },
                    ),
                );
        }

        // TODO: Implement function to get the preview hash of a song
        fn get_preview(self: @ContractState, song_id: u64) -> felt252 {
            // Validate song ID
            let total_songs = self.song_count.read();
            assert!(song_id <= total_songs, "Song ID does not exist");

            // Return preview IPFS hash
            let song = self.songs.read(song_id);
            song.preview_ipfs_hash
        }

        // TODO: Implement function to buy a song and transfer ownership
        fn buy_song(ref self: ContractState, song_id: u64) -> felt252 {
            let buyer = get_caller_address();

            // Validate song ID
            let total_songs = self.song_count.read();
            assert!(song_id <= total_songs, "Song ID does not exist");

            let mut song = self.songs.read(song_id);
            assert!(song.for_sale, "Song is not for sale");
            assert!(song.owner != buyer, "You can't buy your own song");

            // Update song mapping
            let old_owner = song.owner;
            self.user_songs.write((old_owner, song_id), false);

            // Add to buyer's collection
            let buyer_song_count = self.user_song_count.read(buyer);
            self.user_songs.write((buyer, song_id), true);
            self.user_song_ids.write((buyer, buyer_song_count), song_id);
            self.user_song_count.write(buyer, buyer_song_count + 1);

            // Transfer ownership
            song.owner = buyer;
            song.for_sale = false;
            self.songs.write(song_id, song);

            // self.ownable.transfer_ownership(buyer);

            song.ipfs_hash
        }

        fn get_user_songs(self: @ContractState, user: ContractAddress) -> Array<u64> {
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'ZERO_ADDRESS_CALLER');
            // get the count of songs for the user
            let user_song_count = self.user_song_count.read(user);
            // create an array to store the song IDs
            let mut song_ids = ArrayTrait::new();
            // iterate through the user's songs
            let mut i: u64 = 0;
            while i < user_song_count {
                let song_id = self.user_song_ids.read((user, i));
                song_ids.append(song_id);
                i += 1;
            }

            song_ids
        }

        fn is_song_owner(self: @ContractState, song_id: u64) -> bool {
            // check if the song ID is valid
            let user = get_caller_address();
            assert(!user.is_zero(), 'ZERO_ADDRESS_CALLER');
            assert(!song_id.is_zero(), 'ZERO_SONG_ID');

            // check if the song ID is valid
            let total_songs = self.song_count.read();
            if song_id > total_songs {
                return false;
            }

            // check if the user is the owner of the song
            let song = self.songs.read(song_id);
            song.owner == user
        }
    }
}
