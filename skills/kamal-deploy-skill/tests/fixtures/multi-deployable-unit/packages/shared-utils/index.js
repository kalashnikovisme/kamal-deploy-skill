function formatResponse(data) {
  return { ...data, formattedAt: new Date().toISOString() };
}

module.exports = { formatResponse };
