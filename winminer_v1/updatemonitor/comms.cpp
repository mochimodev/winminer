/* comms.cpp Connect, Request, Send/Receive Blocks
 *
 * Copyright (c) 2019 by Adequate Systems, LLC.  All Rights Reserved.
 * See LICENSE.PDF   **** NO WARRANTY ****
 * https://github.com/mochimodev/mochimo/raw/master/LICENSE.PDF
 *
 * Date: 26 January 2019
 *
*/

#include "winminer.h"

int nonblock(SOCKET sd)
{
	u_long arg = 1L;

	return ioctlsocket(sd, FIONBIO, (u_long FAR *) &arg);
}

int blocking(SOCKET sd)
{
	u_long arg = 0L;

	return ioctlsocket(sd, FIONBIO, (u_long FAR *) &arg);
}

word32 str2ip(char *addrstr)
{
	struct hostent *host;
	struct sockaddr_in addr;

	if (addrstr == NULL) return 0;

	memset(&addr, 0, sizeof(addr));
	if (addrstr[0] < '0' || addrstr[0] > '9') {
		host = gethostbyname(addrstr);
		if (host == NULL) {
			printf("str2ip(): gethostbyname() failed\n");
			return 0;
		}
		memcpy((char *) &(addr.sin_addr.s_addr),
			host->h_addr_list[0], host->h_length);
	}
	else
		addr.sin_addr.s_addr = inet_addr(addrstr);

	return addr.sin_addr.s_addr;
} 

SOCKET connectip(word32 ip)
{
	SOCKET sd;
	struct sockaddr_in addr;
	word16 port;
	time_t timeout;
	if ((sd = socket(AF_INET, SOCK_STREAM, 0)) == INVALID_SOCKET) {
		return INVALID_SOCKET;
	}
	port = Port;
	memset((char *)&addr, 0, sizeof(addr));
	addr.sin_addr.s_addr = ip;
	addr.sin_family = AF_INET;  /* AF_UNIX */
	addr.sin_port = htons(port);
	nonblock(sd);
	timeout = time(NULL) + 3;
	Sigint = 0;

retry:
	if (connect(sd, (struct sockaddr *) &addr, sizeof(struct sockaddr))) {
		errno = WSAGetLastError();
		if (errno == WSAEISCONN) goto out;
		if (time(NULL) < timeout && Sigint == 0) goto retry;
		closesocket(sd);
		return INVALID_SOCKET;
	}
out:
	nonblock(sd);
	return sd;
}

int sendtx2(NODE *np)
{
	int count;
	TX *tx;

	tx = &np->tx;

	put16(tx->version, PVERSION);
	put16(tx->network, TXNETWORK);
	put16(tx->trailer, TXEOT);
	put16(tx->id1, np->id1);
	put16(tx->id2, np->id2);
	crctx(tx);
	errno = 0;
	count = send(np->sd, (const char *)TXBUFF(tx), TXBUFFLEN, 0);
	if (count != TXBUFFLEN) {
		if (Trace) printf("sendtx2() errno: %d\n", errno);
		return VERROR;
	}
	return VEOK;
}

int send_op(NODE *np, int opcode)
{
	put16(np->tx.opcode, opcode);
	return sendtx2(np);
}

int rx2(NODE *np, int checkids)
{
	int count, n;
	time_t timeout;
	TX *tx;

	tx = &np->tx;
	timeout = time(NULL) + 3;

	Sigint = 0;
	for (n = 0; ; ) {
		count = recv(np->sd, (char *)TXBUFF(tx) + n, TXBUFFLEN - n, 0);
		if (Sigint) return VERROR;
		if (count == 0) return VERROR;
		if (count < 0) {
			if (time(NULL) >= timeout) return -1;
			continue;
		}
		n += count;
		if (n == TXBUFFLEN) break;
	}
	if (get16(tx->network) != TXNETWORK)
		return 2;
	if (get16(tx->trailer) != TXEOT)
		return 3;
	if (crc16(CRC_BUFF(tx), CRC_COUNT) != get16(tx->crc16))
		return 4;
	if (checkids && (np->id1 != get16(tx->id1) || np->id2 != get16(tx->id2)))
		return 5;
	return VEOK;
}

int callserver(NODE *np, word32 ip)
{
	int ecode, j;

	Sigint = 0;
	memset(np, 0, sizeof(NODE));
	np->sd = connectip(ip);
	if (np->sd == INVALID_SOCKET) return VERROR;
	np->src_ip = ip;
	np->id1 = rand16();

	send_op(np, OP_HELLO);

	ecode = rx2(np, 0);
	if (ecode != VEOK) {
		if (Trace) printf("*** missing HELLO_ACK packet (%d)\n", ecode);
	bad:
		closesocket(np->sd);
		np->sd = INVALID_SOCKET;
		Nextcore++;
		return VERROR;
	}
	np->id2 = get16(np->tx.id2);
	np->opcode = get16(np->tx.opcode);
	if (np->opcode != OP_HELLO_ACK) {
		if (Trace) printf("*** HELLO_ACK is wrong: %d\n", np->opcode);
		goto bad;
	}
	put64(Cblocknum, np->tx.cblock);
	Cbits = np->tx.version[1];
	return VEOK;
}

int set_bnum(byte *bnum, word32 *ip)
{
	NODE node;
	if (callserver(&node, *ip) != VEOK) return VERROR;
	if (bnum == NULL) return VERROR;
	if (bnum != NULL) {
		memcpy(bnum, Cblocknum, 8);
	}
	closesocket(node.sd);
	return VEOK;
}

int get_block3(NODE *np, char *fname)
{
	FILE *fp;
	word16 len;
	int n, ecode;

	if (Trace) printf("get_block3() Recfile is '%s'\n", fname);

	fp = fopen(fname, "wb");
	if (fp == NULL) {
		printf("cannot open %s\n", fname);
		return 1;
	}
	for (;;) {
		if ((ecode = rx2(np, 1)) != VEOK) goto bad;
		if (get16(np->tx.opcode) != OP_SEND_BL) goto bad;
		len = get16(np->tx.len);
		if (len > TRANLEN) goto bad;
		if (len) {
			n = fwrite(TRANBUFF(&np->tx), 1, len, fp);
			if (n != len) {
				if (Trace) printf("get_block3() I/O error\n");
				goto bad;
			}
		}
		if (len < 1 || n < TRANLEN) {
			fclose(fp);
			if (Trace) printf("get_block3(): EOF\n");
			return 0;
		}
	}
bad:
	fclose(fp);
	_unlink(fname);
	if (Trace) printf("get_block3(): fail (%d) len = %d opcode = %d\n",
		ecode, get16(np->tx.len), get16(np->tx.opcode));
	return 1;
}

int get_cblock(word32 ip, char *fname)
{
	NODE node;
	if (callserver(&node, ip) != VEOK) return VERROR;
	put16(node.tx.len, 1);
	printf("\nAttempting to download candidate block from network...");
	send_op(&node, OP_GET_CBLOCK);
	if (get_block3(&node, fname) != 0) {
		closesocket(node.sd);
		Nextcore++;
		return VERROR;
	}
	closesocket(node.sd);
	return VEOK;
}

int send_file(NODE *np, char *fname)
{
	TX *tx;
	int n, status;
	FILE *fp;

	tx = &np->tx;

	fp = fopen(fname, "rb");
	if (fp == NULL) {
		if (Trace) printf("cannot open %s\n", fname);
		return VERROR;
	}
	printf("\nSending solved block: %s", fname);
	blocking(np->sd);
	for (; Running; ) {
		n = fread(TRANBUFF(tx), 1, TRANLEN, fp);
		put16(tx->len, n);
		status = send_op(np, OP_SEND_BL);
		if (n < TRANLEN) {
			fclose(fp);
			return status;
		}
		if (status != VEOK) break;
	}
	fclose(fp);
	return VERROR;
}

int send_mblock(char *fname)
{
	NODE node;
	int status;

	if (!exists(fname)) return VERROR;
	if (callserver(&node, 0) != VEOK) return VERROR;
	put16(node.tx.len, 1);
	send_op(&node, OP_MBLOCK);
	status = send_file(&node, fname);
	closesocket(node.sd);
	return status;
}
