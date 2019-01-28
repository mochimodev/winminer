/* Multi-byte numbers are little-endian.
 * Structure is checked on start-up for byte-alignment.
 * HASHLEN is checked to be 32.
 */
typedef struct {
	byte version[2];  /* 0x01, 0x00 PVERSION  */
	byte network[2];  /* 0x39, 0x05 TXNETWORK */
	byte id1[2];
	byte id2[2];
	byte opcode[2];
	byte cblock[8];        /* current block num  64-bit */
	byte blocknum[8];      /* block num for I/O in progress */
	byte cblockhash[32];   /* sha-256 hash of our current block */
	byte pblockhash[32];   /* sha-256 hash of our previous block */
	byte weight[32];       /* sum of block difficulties */
	byte len[2];  /* length of data in transaction buffer for I/O op's */
	/* start transaction buffer */
	byte src_addr[TXADDRLEN];
	byte dst_addr[TXADDRLEN];
	byte chg_addr[TXADDRLEN];
	byte send_total[TXAMOUNT];
	byte change_total[TXAMOUNT];
	byte tx_fee[TXAMOUNT];
	byte tx_sig[TXSIGLEN];
	/* end transaction buffer */
	byte crc16[2];
	byte trailer[2];  /* 0xcd, 0xab */
} TX;


/* stripped-down NODE for rx2() and callserver(): */
typedef struct {
	TX tx;  /* transaction buffer */
	word16 id1;      /* from tx */
	word16 id2;      /* from tx */
	int opcode;      /* from tx */
	word32 src_ip;
	SOCKET sd;
	pid_t pid;     /* process id of child -- zero if empty slot */
} NODE;


/* The block trailer at end of block file */
typedef struct {
	byte phash[HASHLEN];    /* previous block hash (32) */
	byte bnum[8];           /* this block number */
	byte mfee[8];           /* transaction fee */
	byte tcount[4];         /* transaction count */
	byte time0[4];          /* to compute next difficulty */
	byte difficulty[4];
	byte mroot[HASHLEN];  /* hash of all TXQENTRY's */
	byte nonce[HASHLEN];
	byte stime[4];        /* unsigned start time GMT seconds */
	byte bhash[HASHLEN];  /* hash of all block less bhash[] */
} BTRAILER;
