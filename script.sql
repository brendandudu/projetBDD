############################## Création des tables (partie commune) ##############################

CREATE DATABASE IF NOT EXISTS projetBDD;
USE projetBDD;

CREATE TABLE IF NOT EXISTS lodging (
id INT AUTO_INCREMENT NOT NULL, 
lodging_type_id INT NOT NULL, 
name VARCHAR(255) NOT NULL, 
capacity INT NOT NULL, 
space INT NOT NULL,
internet_available TINYINT(1) NOT NULL, 
description LONGTEXT NOT NULL, 
night_price DOUBLE PRECISION NOT NULL,
updated_at DATETIME DEFAULT NULL,
lat DECIMAL(10,8),
lng DECIMAL(10,8),
address VARCHAR(255),
city VARCHAR(255),
user_id INT NOT NULL, 
created_at DATETIME DEFAULT NULL,
PRIMARY KEY (id),
FOREIGN KEY (user_id) REFERENCES user(id),
FOREIGN KEY (lodging_type_id) REFERENCES lodging_type(id)
);

CREATE TABLE IF NOT EXISTS lodging_type (
id INT NOT NULL,
type_name VARCHAR(255) NOT NULL,
PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS booking (
id INT AUTO_INCREMENT NOT NULL, 
user_id INT NOT NULL,
lodging_id INT NOT NULL,
booking_state_id INT NOT NULL,
booked_at DATETIME DEFAULT NULL,
total_pricing DOUBLE PRECISION NOT NULL,
total_occupiers INT NOT NULL,
begins_at DATE NOT NULL, 
ends_at DATE NOT NULL CHECK(DATEDIFF(begins_at, ends_at) > 0), 
PRIMARY KEY (id),
FOREIGN KEY (user_id) REFERENCES user(id),
FOREIGN KEY (lodging_id) REFERENCES lodging(id),
FOREIGN KEY (booking_state_id) REFERENCES booking_state(id)
);

CREATE TABLE IF NOT EXISTS booking_state (
id INT NOT NULL,
type_name VARCHAR(255) NOT NULL,
PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS user (
id INT AUTO_INCREMENT NOT NULL, 
email VARCHAR(180) NOT NULL,
password VARCHAR(255) NOT NULL, 
first_name VARCHAR(255) NOT NULL, 
last_name VARCHAR(255) NOT NULL,
created_at DATETIME DEFAULT NULL,   
deleted_at DATETIME DEFAULT NULL, 
user_type ENUM('host', 'admin', 'guest'),
updated_at DATETIME DEFAULT NULL,
phone varchar(15),
PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS comment (
user_id INT NOT NULL,
lodging_id INT NOT NULL,
note INT NOT NULL CHECK (note <= 5),
comment LONGTEXT NOT NULL,
created_at DATETIME DEFAULT NULL,
updated_at DATETIME DEFAULT NULL,
FOREIGN KEY (user_id) REFERENCES user(id),
FOREIGN KEY (lodging_id) REFERENCES lodging(id)
);

CREATE TABLE IF NOT EXISTS wishlist (
user_id INT NOT NULL,
lodging_id INT NOT NULL,
FOREIGN KEY (user_id) REFERENCES user(id),
FOREIGN KEY (lodging_id) REFERENCES lodging(id)
);

############################## Fin création des tables (partie commune) ##############################








############################## PARTIE BRENDAN (GESTION DES ANNONCES) ##############################

/* Triggers */

-- set updated date --
DELIMITER |
CREATE trigger before_update_lodging
BEFORE UPDATE
ON lodging for each row
BEGIN
	SET NEW.updated_at = NOW();
END |
DELIMITER ;

-- set created date --
DELIMITER |
CREATE trigger before_insert_lodging
BEFORE insert
ON lodging for each row
BEGIN
	SET NEW.created_at = NOW();
END |
DELIMITER ;

/* Fin triggers */

/* Indexes */

 -- Permet d'obtenir les hébergements à proximité plus rapidement (INDEX UNIQUE) --
CREATE UNIQUE INDEX location
ON lodging (lat, lng);

/* Fin indexes */

/* Function */

-- calcule la distance entre deux points --
DELIMITER $$
CREATE FUNCTION calculDistance(
	lat DECIMAL(10,8), 
    lng DECIMAL(10,8), 
    search_lat DECIMAL(10,8), 
    search_lng DECIMAL(10,8)
) 
RETURNS FLOAT
DETERMINISTIC
BEGIN
    DECLARE dist FLOAT;

    SET dist = 3959 * acos( 
		cos(radians(search_lat)) 
		* cos(radians(lat)) 
		* cos(radians(lng) - radians(search_lng)) 
		+ sin(radians(search_lat)) 
		* sin(radians(lat)) 
	);
    
    RETURN (dist);
END $$
DELIMITER ;

/* Fin function */

/* Stored procedures */

-- Sélectionne tout les hébergements (+ nb résultat + prix moyen), dans un rayon de 30 km autour du point de recherche (utilise la function calcDistance) + disponible entre les deux dates désirées + dispose de la capacité d'acceuil demandée
DELIMITER $$
CREATE PROCEDURE selectLodgingByCriteria
(
	search_lat DECIMAL(10,8),
	search_lgn DECIMAL(10,8),
    dt_begin DATE,
    dt_end DATE,
    capacity INT
)
BEGIN
	DECLARE radius FLOAT;
	SET radius = 30;
    
    SELECT *,  calculDistance(lat, lng, search_lat, search_lgn) AS distance, count(*) as nbResultat, avg()
    FROM Lodging l
	LEFT JOIN Booking b ON l.id = b.lodging_id
	WHERE (
		(dt_end <= b.begins_at OR dt_begin >= b.ends_at) -- Soit l'hébergement est déja dans Booking mais est disponible pour ces dates
	OR 
	(
		(dt_begin <= b.ends_at AND dt_end >= b.begins_at)  -- Soit il était déja réservé pour ces dates mais la réservation est annulée/terminée
        AND 
        (b.booking_state_id = 4 OR b.booking_state_id = 1)
	)
    OR 
		b.lodging_id IS NULL -- Soit il n'est toujours pas dans Booking
	)
    AND
		l.capacity >= capacity
	HAVING 
		distance <= radius
    ORDER BY 
		distance ASC;
END $$
DELIMITER ;

-- Selectionne les 5 hébergenents les plus réservées --
DELIMITER $$
CREATE PROCEDURE selectFiveMostPopular()
BEGIN
    
    SELECT count(*) AS nbReservation, lodging.id 
    FROM lodging, booking 
    WHERE lodging.id = booking.lodging_id 
    GROUP BY lodging.id 
    ORDER BY nbReservation DESC 
    LIMIT 5;

END $$
DELIMITER ;

-- Selectionne l'hébergenent le plus réservé --
DELIMITER $$
CREATE PROCEDURE selectTheMostPopular()
BEGIN
    
    SELECT max(nbReservation) AS totalReservation, id
	FROM (
		SELECT lodging.id AS id, count(*) AS nbReservation
		FROM lodging, booking
		WHERE lodging.id = booking.lodging_id
		GROUP BY id
	) AS mostPopular ;

END $$
DELIMITER ;

-- Selectionne le type d'hébergement le plus réservé --
DELIMITER $$
CREATE PROCEDURE selectTheMostPopularType()
BEGIN
    
    SELECT type_name
	FROM (
		SELECT count(*) AS nbReservation, lt.type_name
		FROM lodging AS l, booking AS b, lodging_type AS lt
		WHERE l.id = b.lodging_id
        AND lt.id = l.lodging_type_id 
		GROUP BY lt.id
	)  AS mostPop
    HAVING MAX(nbReservation);

END $$
DELIMITER ;

-- Selectionne les hébergements réservés aujourd'hui --
DELIMITER $$
CREATE PROCEDURE selectLodgingBookedToday()
BEGIN
    
    SELECT lodging.id
	FROM lodging, booking
	WHERE lodging.id = booking.lodging_id
	AND DATE(booking.booked_at) = CURRENT_DATE()
	GROUP BY lodging.id;

END $$
DELIMITER ;

-- Selectionne les hébergements possédés par un hôte --
DELIMITER $$
CREATE PROCEDURE selectLodgingByOwnerId(owner_id int)
BEGIN
    
    SELECT lodging.id
	FROM lodging
    WHERE lodging.owner_id = owner_id;

END $$
DELIMITER ;


-- Supprime un hébergement --
DELIMITER $$
CREATE PROCEDURE deleteLodging(id INT)
BEGIN
    
    DELETE FROM lodging
	WHERE lodging.id = id;

END $$
DELIMITER ;

-- Modifie le prix par nuit d'un hébergement --
DELIMITER $$
CREATE PROCEDURE updateLodgingPrice(id INT, new_price FLOAT)
BEGIN
    
    UPDATE lodging
    SET night_price = new_price
    WHERE lodging.id = id;

END $$
DELIMITER ;

-- Selectionne les hébergements occupés à une date --
DELIMITER $$
CREATE PROCEDURE selectLodgingUnavailableByDate(dateDemande DATE)
BEGIN
    
    SELECT lodging.*
    FROM booking, lodging
    WHERE booking.lodging_id = lodging.id
    AND dateDemande BETWEEN booking.begins_at AND booking.ends_at;

END $$
DELIMITER ;

-- Selectionne le nombre d'occupant moyen par hébergement --
DELIMITER $$
CREATE PROCEDURE selectAvarageOccupiers(owner_id INT)
BEGIN
    
    SELECT CONVERT(avg(total_occupiers),SIGNED INTEGER) AS averageOccupiers, lodging_id
    FROM booking
    GROUP BY booking.lodging_id;

END $$
DELIMITER ;

-- Selectionne les hébergement par type --
DELIMITER $$
CREATE PROCEDURE selectLodgingByTypeName(typeName varchar(20))
BEGIN
    
    SELECT lodging.*
    FROM lodging, lodging_type
    WHERE lodging.lodging_type_id = lodging_type.id
    AND lodging_type.type_name = typeName;

END $$
DELIMITER ;

/* Fin stored procedures */

############################## Fin PARTIE BRENDAN (GESTION DES ANNONCES) ##############################








############################## PARTIE LOUIS (GESTION DES RESERVATIONS) ##############################

/* Triggers */

-- set booked date --
DELIMITER |
CREATE trigger before_insert_booking
BEFORE insert
ON booking for each row
BEGIN
	SET NEW.booked_at = NOW();
END |
DELIMITER ;

-- set calculated totalPricing --
DELIMITER |
CREATE trigger before_insert_booking_totalPricing
BEFORE insert
ON booking for each row
BEGIN
	SET NEW.total_pricing = datediff(NEW.ends_at, NEW.begins_at)
    * (select night_price FROM lodging WHERE id = NEW.lodging_id);
END |
DELIMITER ;

/* Fin triggers */


/* Indexes */

 -- Permet d'obtenir les hébergements disponibles plus rapidement --
CREATE INDEX availability
ON booking (begins_at, ends_at);

/* Fin indexes */


/* Stored procedures */

-- Selectionne les réservations qui commence aujourd'hui
DELIMITER $$
CREATE PROCEDURE selectBookingThatStartToday()
BEGIN
    
    SELECT *
    FROM booking
    WHERE begins_at = CURRENT_DATE();

END $$
DELIMITER ;

-- Selectionne les réservations qui se termine aujourd'hui --
DELIMITER $$
CREATE PROCEDURE selectBookingThatEndToday()
BEGIN
    
    SELECT *
    FROM booking
    WHERE ends_at = CURRENT_DATE();

END $$
DELIMITER ;

-- Selectionne les réservations qui ont été prises aujourd'hui --
DELIMITER $$
CREATE PROCEDURE selectBookingMakeToday()
BEGIN
    
    SELECT *
    FROM booking
    WHERE DATE(booked_at) = CURRENT_DATE();

END $$
DELIMITER ;

-- Selectionne les réservations prise par un guest --
DELIMITER $$
CREATE PROCEDURE selectBookingByBuyerId(buyer_id INT)
BEGIN
    
    SELECT *
    FROM booking
    WHERE booking.user_id = buyer_id;

END $$
DELIMITER ;

-- Selectionne les réservations qui concerne les hébergements d'un hôte en particulier --
DELIMITER $$
CREATE PROCEDURE selectBookingByLodgingOwnerId(owner_id INT)
BEGIN
    
    SELECT *
    FROM booking, lodging
    WHERE booking.lodging_id = lodging.id
    AND lodging.user_id = owner_id;

END $$
DELIMITER ;

-- Selectionne le chiffre d'affaire total rapporté par toutes les réservations d'un hôte  --
DELIMITER $$
CREATE PROCEDURE selectCAByOwnerId(owner_id INT)
BEGIN
    
    SELECT sum(booking.total_pricing)
    FROM booking, lodging
    WHERE booking.lodging_id = lodging.id
    AND lodging.user_id = owner_id;

END $$
DELIMITER ;

-- Annule une réservation (modifie son statut)  --
DELIMITER $$
CREATE PROCEDURE cancelBooking(id INT)
BEGIN
    
    UPDATE booking
    SET booking_state_id = 4
    WHERE booking.id = id;

END $$
DELIMITER ;

-- Modifie le nombre d'occupant --
DELIMITER $$
CREATE PROCEDURE updateOccupiersNumber(id INT, new_occupiers INT)
BEGIN
    
    UPDATE booking
    SET total_occupiers = new_occupiers
    WHERE booking.id = id;

END $$
DELIMITER ;

/* Fin Stored procedures */

############################## Fin PARTIE LOUIS (GESTION DES RESERVATIONS) ##############################








############################## PARTIE ABEL (GESTION DES UTILISATEURS) ##############################

/* Triggers */

-- set created date --
DELIMITER |
CREATE trigger before_insert_user
BEFORE insert
ON user for each row
BEGIN
	SET NEW.created_at = NOW();
END |
DELIMITER ;

-- set updated date --
DELIMITER |
CREATE trigger before_update_user
BEFORE UPDATE
ON user for each row
BEGIN
	SET NEW.updated_at = NOW();
END |
DELIMITER ;

/* Fin trigger */


/* Indexes */

 -- Permet d'appliquer un champs unique sur email (UNIQUE INDEX) --
CREATE UNIQUE INDEX email
ON user (email);

/* Fin indexes */


/* Stored procedures */

-- Supprime un utilisateur (met à jour le champs deleted_at) --
DELIMITER $$
CREATE PROCEDURE deleteUser(user_id INT)
BEGIN
    
    UPDATE user 
    SET deleted_at = NOW()
    WHERE user.id = user_id;

END $$
DELIMITER ;

-- Modifie le mot de passe --
DELIMITER $$
CREATE PROCEDURE updateUserPassword(user_id INT, new_password VARCHAR(100))
BEGIN
    
    UPDATE user 
    SET password = MD5(new_password)
    WHERE user.id = user_id;

END $$
DELIMITER ;

-- Modifie le nom --
DELIMITER $$
CREATE PROCEDURE updateUserName(user_id INT, new_first_name VARCHAR(100))
BEGIN
    
    UPDATE user 
    SET first_name = new_first_name
    WHERE user.id = user_id;

END $$
DELIMITER ;

-- Selectionne l'utilisateur possédant cet email --
DELIMITER $$
CREATE PROCEDURE selectUserByEmail(search_email VARCHAR(100))
BEGIN
    
    SELECT *
    FROM user 
    WHERE email = search_email;

END $$
DELIMITER ;

-- Selectionne le nombre total d'utilisateur --
DELIMITER $$
CREATE PROCEDURE selectUserCount()
BEGIN
    
    SELECT count(*) as nbUsers
    FROM user;

END $$
DELIMITER ;


-- Selectionne le temps de séjour moyen pour l'utilisateur --
DELIMITER $$
CREATE PROCEDURE selectAverageResidenceTime(user_id INT)
BEGIN
    
    SELECT ROUND(AVG(datediff(ends_at, begins_at)))
    FROM booking, user
    WHERE booking.user_id = user.id
    AND user.id = user_id;

END $$
DELIMITER ;

-- Selectionne les utilisateurs en fonction de leur type (admin, host, guest) --
DELIMITER $$
CREATE PROCEDURE selectByUserType(typeName varchar(20))
BEGIN
    
    SELECT user.id, user.first_name, user.last_name
    FROM user
    WHERE user_type = typeName;

END $$
DELIMITER ;

-- Selectionne le nombre de réservation effectué par l'utilisateur --
DELIMITER $$
CREATE PROCEDURE selectBookingCountByUser(user_id INT)
BEGIN
    
    SELECT COUNT(*)
    FROM booking, user
    WHERE booking.user_id = user.id
    AND user.id = user_id;

END $$
DELIMITER ;

/* Fin Stored procedures */

############################## Fin PARTIE ABEL (GESTION DES UTILISATEURS) ##############################







############################## PARTIE DAVID (GESTION DES WISHLIST + COMMENT) ##############################

/* Triggers */

-- set created date --
DELIMITER |
CREATE trigger before_insert_comment
BEFORE insert
ON comment for each row
BEGIN
	SET NEW.created_at = NOW();
END |
DELIMITER ;

-- set updated date --
DELIMITER |
CREATE trigger before_update_comment
BEFORE UPDATE
ON comment for each row
BEGIN
	SET NEW.updated_at = NOW();
END |
DELIMITER ;

/* Fin triggers */


/* Stored procedure */

-- Selectionne les hébergements dans la wishlist de l'utilisateur --
DELIMITER $$
CREATE PROCEDURE selectLodgingFromWishlist(user_id INT)
BEGIN
    
    SELECT lodging.*
    FROM wishlist, lodging
    WHERE wishlist.user_id = user_id
    AND wishlist.lodging_id = lodging.id;

END $$
DELIMITER ;

-- Selectionne le prix moyen de tout les hébergements dans wishlist --
DELIMITER $$
CREATE PROCEDURE selectAveragePriceFromWishlist(user_id INT)
BEGIN
    
    SELECT ROUND(AVG(night_price), 2)
    FROM wishlist, lodging
    WHERE wishlist.user_id = user_id
    AND wishlist.lodging_id = lodging.id;

END $$
DELIMITER ;

-- Selectionne le nombre d'hébergements dans wishlist --
DELIMITER $$
CREATE PROCEDURE selectAveragePriceFromWishlist(user_id INT)
BEGIN
    
    SELECT count(*)
    FROM wishlist, lodging
    WHERE wishlist.user_id = user_id
    AND wishlist.lodging_id = lodging.id;

END $$
DELIMITER ;




-- Selectionne la note moyenne d'un hébergement --
DELIMITER $$
CREATE PROCEDURE selectAverageNote(lodging_id INT)
BEGIN
    
    SELECT ROUND(AVG(note),1) as average_note
    FROM comment
    WHERE comment.lodging_id = lodging_id;

END $$
DELIMITER ;

-- Selectionne les commentaires d'un hébergement --
DELIMITER $$
CREATE PROCEDURE selectCommentByLodging(lodging_id INT)
BEGIN
    
    SELECT comment.*
    FROM comment, lodging
    WHERE comment.lodging_id = lodging.id 
    AND lodging.id = lodging_id;

END $$
DELIMITER ;

-- Selectionne les commentaires d'un hébergement par meilleure note --
DELIMITER $$
CREATE PROCEDURE selectCommentByLodgingOrderByBestNote(lodging_id INT)
BEGIN
    
    SELECT comment.*
    FROM comment, lodging
    WHERE comment.lodging_id = lodging.id 
    AND lodging.id = lodging_id
    ORDER BY comment.note DESC;

END $$
DELIMITER ;

-- Selectionne les commentaires d'un hébergement par plus récent --
DELIMITER $$
CREATE PROCEDURE selectCommentByLodgingOrderByMoreRecent(lodging_id INT)
BEGIN
    
    SELECT comment.*
    FROM comment, lodging
    WHERE comment.lodging_id = lodging.id 
    AND lodging.id = lodging_id
    ORDER BY comment.created_at DESC;

END $$
DELIMITER ;

-- Modifie un commentaire --
DELIMITER $$
CREATE PROCEDURE updateComment(comment_id INT, new_note INT, new_comment VARCHAR(255))
BEGIN
    
    UPDATE comment
    SET comment = new_comment, note = new_note
    WHERE comment.id = comment_id;

END $$
DELIMITER ;

-- Selectionne le nombre de commentaire pour un hébergement --
DELIMITER $$
CREATE PROCEDURE updateComment(lodging_id INT)
BEGIN
    
    SELECT count(*)
    FROM comment, lodging
    WHERE comment.lodging_id = lodging_id
    AND comment.lodging_id = lodging.id;

END $$
DELIMITER ;

/* Fin stored procedure */

############################## Fin PARTIE DAVID (GESTION DES WISHLIST + COMMENT) ##############################