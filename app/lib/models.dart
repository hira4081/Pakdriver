double _d(dynamic v) => (v as num).toDouble();
double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

const vehicleTypes = ['bike', 'rickshaw', 'car'];
String vehicleLabel(String t) => switch (t) {
      'bike' => 'Bike',
      'rickshaw' => 'Rickshaw',
      _ => 'Car',
    };

class Place {
  final String label;
  final double lat;
  final double lng;
  const Place(this.label, this.lat, this.lng);
  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(j['label'] as String, _d(j['lat']), _d(j['lng']));
  Map<String, dynamic> toJson() => {'label': label, 'lat': lat, 'lng': lng};
}

class Vehicle {
  final String type;
  final String? make, model, color, plate;
  const Vehicle(this.type, this.make, this.model, this.color, this.plate);
  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
      j['type'] as String? ?? 'car', j['make'] as String?, j['model'] as String?, j['color'] as String?, j['plate'] as String?);

  String get title {
    final parts = [color, make, model].where((e) => e != null && e.isNotEmpty).join(' ');
    return parts.isEmpty ? vehicleLabel(type) : parts;
  }
}

class Me {
  final int id;
  final String email, name, role;
  final String? picture, phone;
  final double? rating;
  final int ratingCount, tripsCount;
  final Vehicle? vehicle;
  final bool isOnline, needsSetup;
  const Me({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.picture,
    this.phone,
    this.rating,
    required this.ratingCount,
    required this.tripsCount,
    this.vehicle,
    required this.isOnline,
    required this.needsSetup,
  });
  bool get isDriver => role == 'driver';
  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'] as int,
        email: j['email'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        picture: j['picture'] as String?,
        phone: j['phone'] as String?,
        rating: _dn(j['rating']),
        ratingCount: j['ratingCount'] as int,
        tripsCount: j['tripsCount'] as int,
        vehicle: j['vehicle'] == null ? null : Vehicle.fromJson(j['vehicle'] as Map<String, dynamic>),
        isOnline: j['isOnline'] as bool,
        needsSetup: j['needsSetup'] as bool,
      );
}

class Person {
  final int id;
  final String name;
  final double? rating;
  final int? trips;
  final String? phone;
  final double? lat, lng;
  final Vehicle? vehicle;
  const Person({required this.id, required this.name, this.rating, this.trips, this.phone, this.lat, this.lng, this.vehicle});
  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as int,
        name: j['name'] as String,
        rating: _dn(j['rating']),
        trips: j['trips'] as int?,
        phone: j['phone'] as String?,
        lat: _dn(j['lat']),
        lng: _dn(j['lng']),
        vehicle: j['vehicle'] == null ? null : Vehicle.fromJson(j['vehicle'] as Map<String, dynamic>),
      );
}

class Ride {
  final int id;
  final String status, myRole, vehicleType;
  final Place pickup, dropoff;
  final double distanceKm;
  final int offeredFare;
  final int? acceptedFare, myRating;
  final String? cancelledBy;
  final Person passenger;
  final Person? driver;
  const Ride({
    required this.id,
    required this.status,
    required this.myRole,
    required this.vehicleType,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.offeredFare,
    this.acceptedFare,
    this.myRating,
    this.cancelledBy,
    required this.passenger,
    this.driver,
  });
  int get fare => acceptedFare ?? offeredFare;
  bool get isRider => myRole == 'rider';
  factory Ride.fromJson(Map<String, dynamic> j) => Ride(
        id: j['id'] as int,
        status: j['status'] as String,
        myRole: j['myRole'] as String,
        vehicleType: j['vehicleType'] as String,
        pickup: Place.fromJson(j['pickup'] as Map<String, dynamic>),
        dropoff: Place.fromJson(j['dropoff'] as Map<String, dynamic>),
        distanceKm: _d(j['distanceKm']),
        offeredFare: j['offeredFare'] as int,
        acceptedFare: j['acceptedFare'] as int?,
        myRating: j['myRating'] as int?,
        cancelledBy: j['cancelledBy'] as String?,
        passenger: Person.fromJson(j['passenger'] as Map<String, dynamic>),
        driver: j['driver'] == null ? null : Person.fromJson(j['driver'] as Map<String, dynamic>),
      );
}

class Bid {
  final int id, fare, etaMinutes;
  final Person driver;
  const Bid(this.id, this.fare, this.etaMinutes, this.driver);
  factory Bid.fromJson(Map<String, dynamic> j) =>
      Bid(j['id'] as int, j['fare'] as int, j['etaMinutes'] as int, Person.fromJson(j['driver'] as Map<String, dynamic>));
}

class Nearby {
  final int id, offeredFare;
  final String passengerName;
  final double? passengerRating;
  final Place pickup, dropoff;
  final double distanceKm, pickupAwayKm;
  final int? myBid;
  const Nearby({
    required this.id,
    required this.offeredFare,
    required this.passengerName,
    this.passengerRating,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.pickupAwayKm,
    this.myBid,
  });
  factory Nearby.fromJson(Map<String, dynamic> j) => Nearby(
        id: j['id'] as int,
        offeredFare: j['offeredFare'] as int,
        passengerName: j['passengerName'] as String,
        passengerRating: _dn(j['passengerRating']),
        pickup: Place.fromJson(j['pickup'] as Map<String, dynamic>),
        dropoff: Place.fromJson(j['dropoff'] as Map<String, dynamic>),
        distanceKm: _d(j['distanceKm']),
        pickupAwayKm: _d(j['pickupAwayKm']),
        myBid: j['myBid'] as int?,
      );
}

class TripRow {
  final int id, fare;
  final String status, pickup, dropoff, role, counterpart;
  final DateTime? createdAt;
  const TripRow(this.id, this.fare, this.status, this.pickup, this.dropoff, this.role, this.counterpart, this.createdAt);
  factory TripRow.fromJson(Map<String, dynamic> j) => TripRow(
        j['id'] as int,
        j['fare'] as int,
        j['status'] as String,
        j['pickup'] as String,
        j['dropoff'] as String,
        j['role'] as String,
        j['counterpart'] as String,
        _t(j['createdAt']),
      );
}

class Board {
  final Me me;
  final Ride? ride;
  final List<Bid> bids;
  final List<Nearby> nearby;
  final int wallet;
  final List<TripRow> trips;
  const Board({required this.me, this.ride, required this.bids, required this.nearby, required this.wallet, required this.trips});
  factory Board.fromJson(Map<String, dynamic> j) => Board(
        me: Me.fromJson(j['me'] as Map<String, dynamic>),
        ride: j['ride'] == null ? null : Ride.fromJson(j['ride'] as Map<String, dynamic>),
        bids: (j['bids'] as List).map((e) => Bid.fromJson(e as Map<String, dynamic>)).toList(),
        nearby: (j['nearby'] as List).map((e) => Nearby.fromJson(e as Map<String, dynamic>)).toList(),
        wallet: j['wallet'] as int,
        trips: (j['trips'] as List).map((e) => TripRow.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
