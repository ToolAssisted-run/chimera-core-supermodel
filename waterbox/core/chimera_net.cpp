/* chimera_net.cpp - the network Supermodel's net board would use: none.
 *
 * The net board links two cabinets over TCP (upstream's Src/Network, built
 * on SDL_net). The sandbox has no network, and a frame-by-frame movie has one
 * machine. The core turns the network off (Network = 0), so these are never
 * reached; they are here because the net board's code names them. A
 * connection is never made and nothing is sent.
 */
#include "Network/NetServer.h"
#include "Network/TCPConnection.h"

std::shared_ptr<CTCPConnection> CNetServer::Connect(const std::string &, uint16_t) { return nullptr; }
CNetServer::Registration CNetServer::RegisterHandler(uint32_t, MessageHandler) { return Registration(); }
CNetServer::Registration CNetServer::RegisterDisconnectHandler(DisconnectHandler) { return Registration(); }
void CNetServer::Registration::Reset(void) { m_id = 0; }
CNetServer::Registration &CNetServer::Registration::operator=(Registration &&other) noexcept
{
	m_handlers = std::move(other.m_handlers);
	m_id = other.m_id;
	other.m_id = 0;
	return *this;
}
CNetServer::Registration::Registration(Registration &&other) noexcept : m_handlers(std::move(other.m_handlers)), m_id(other.m_id) { other.m_id = 0; }
CNetServer::Registration::~Registration(void) {}

bool CTCPConnection::Send(const void *, size_t) { return false; }
bool CTCPConnection::Send(std::vector<uint8_t>) { return false; }
void CTCPConnection::Close(void) {}
